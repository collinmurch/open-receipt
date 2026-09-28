import Contacts
import ContactsUI
import SwiftUI

struct ReceiptPeopleView: View {
  let draft: ReceiptDraft
  private let contactClient: ContactClient
  private let receiptStorage: ReceiptStorageClient
  @State private var contactModel: PeoplePickerModel
  @State private var peopleModel: SavedPeopleModel
  @State private var isNewPersonPresented = false
  @State private var haptic = HapticEvent()
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL

  init(
    draft: ReceiptDraft,
    contactClient: ContactClient,
    peopleStorage: PeopleStorageClient,
    receiptStorage: ReceiptStorageClient
  ) {
    self.draft = draft
    self.contactClient = contactClient
    self.receiptStorage = receiptStorage
    contactModel = PeoplePickerModel(client: contactClient)
    peopleModel = SavedPeopleModel(storage: peopleStorage)
  }

  var body: some View {
    @Bindable var contactModel = contactModel

    NavigationStack {
      List {
        selectedPeopleSection

        Section {
          Button("New Person", systemImage: "person.crop.circle.badge.plus") {
            isNewPersonPresented = true
          }
        }

        if !peopleModel.people.isEmpty {
          savedPeopleSection
        }

        if contactModel.isLoading || peopleModel.isLoading {
          Section {
            HStack {
              Spacer()
              ProgressView("Loading people")
              Spacer()
            }
          }
        } else if contactModel.canReadContacts {
          contactsSection
        } else {
          unavailableContactsSection
        }

        if let errorDescription = contactModel.errorDescription ?? peopleModel.errorDescription {
          Section {
            Label(errorDescription, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.secondary)
            Button("Retry") {
              Task { await load() }
            }
          }
        }
      }
      .navigationTitle("People")
      .navigationBarTitleDisplayMode(.inline)
      .haptics(haptic)
      .searchable(text: $contactModel.searchText, prompt: "Search people")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $isNewPersonPresented) {
        NewPersonView { name in
          Task {
            guard let person = await peopleModel.include(name: name) else { return }
            draft.addPerson(person)
            haptic.play(.selection)
          }
        }
      }
      .contactAccessPicker(isPresented: $contactModel.isContactAccessPickerPresented) {
        identifiers in
        Task { await addResolvedContacts(identifiers) }
      }
      .task { await load() }
      .onReceive(
        NotificationCenter.default.publisher(for: .CNContactStoreDidChange)
      ) { _ in
        Task { await contactModel.reload() }
      }
    }
  }

  private var selectedPeopleSection: some View {
    Section("On This Receipt") {
      ForEach(draft.participants) { participant in
        if participant.source.isCurrentUser {
          NavigationLink {
            OwnerContactPicker(
              contactClient: contactClient,
              selectedIdentifier: participant.source.contactIdentifier,
              onSelect: selectOwner)
          } label: {
            participantLabel(participant) {
              Text("Owner")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        } else {
          participantLabel(participant) {
            Button("Remove \(participant.displayName)", systemImage: "minus.circle") {
              removeParticipant(participant.id)
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func participantLabel(
    _ participant: ReceiptParticipant,
    @ViewBuilder accessory: () -> some View
  ) -> some View {
    HStack(spacing: 12) {
      PersonAvatarView(
        name: participant.displayName,
        imageData: participant.avatarData)
      Text(participant.displayName)
      Spacer()
      accessory()
    }
  }

  private var ownerContactIdentifier: String? {
    draft.currentUser?.source.contactIdentifier
  }

  private func selectOwner(_ contact: ContactSummary?) {
    guard let contact else {
      draft.setOwner(nil)
      haptic.play(.selection)
      return
    }
    let owner = ReceiptOwner(contact)
    Task {
      let avatar = await contactModel.avatar(for: contact.identifier)
      draft.setOwner(owner, avatarData: avatar)
      haptic.play(.selection)
      await peopleModel.adoptOwner(owner)
    }
  }

  private var savedPeopleSection: some View {
    Section("Saved People") {
      ForEach(filteredSavedPeople) { person in
        let participant =
          draft.participant(forPersonID: person.id)
          ?? person.contactIdentifier.flatMap(draft.participant(forContactIdentifier:))
        Button {
          if let participant {
            removeParticipant(participant.id)
          } else {
            Task {
              guard let included = await peopleModel.include(person) else { return }
              let avatar = await avatar(for: included.contactIdentifier)
              draft.addPerson(included, avatarData: avatar)
              haptic.play(.selection)
            }
          }
        } label: {
          HStack(spacing: 12) {
            PersonAvatarView(
              name: person.displayName,
              imageData: person.contactIdentifier.flatMap { contactModel.avatars[$0] })
            Text(person.displayName)
              .foregroundStyle(.primary)
            Spacer()
            if participant != nil {
              Image(systemName: "checkmark")
                .fontWeight(.semibold)
            }
          }
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .task(id: person.contactIdentifier) {
          _ = await avatar(for: person.contactIdentifier)
        }
      }
    }
  }

  private var contactsSection: some View {
    Section("Contacts") {
      if contactModel.authorization == .limited {
        Button("Choose More Contacts", systemImage: "person.crop.circle.badge.plus") {
          contactModel.isContactAccessPickerPresented = true
        }

        if !contactModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          ContactAccessButton(queryString: contactModel.searchText) { identifiers in
            Task { await addResolvedContacts(identifiers) }
          }
        }
      }

      if contactModel.filteredContacts.isEmpty {
        Text("No matching contacts")
          .foregroundStyle(.secondary)
      } else {
        ForEach(
          contactModel.filteredContacts.filter { $0.identifier != ownerContactIdentifier }
        ) { contact in
          contactRow(contact)
        }
      }
    }
  }

  private var unavailableContactsSection: some View {
    Section("Contacts") {
      if contactModel.authorization == .restricted {
        Text("Contacts are unavailable because this device restricts access.")
          .foregroundStyle(.secondary)
      } else if contactModel.authorization == .denied {
        Text("Allow Contacts access in Settings to add people from your contacts.")
          .foregroundStyle(.secondary)
        Button("Open Settings") {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          openURL(url)
        }
      }
    }
  }

  private var filteredSavedPeople: [Person] {
    let query = contactModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let people = peopleModel.people.filter {
      $0.contactIdentifier == nil || $0.contactIdentifier != ownerContactIdentifier
    }
    guard !query.isEmpty else { return people }
    return people.filter {
      $0.displayName.localizedCaseInsensitiveContains(query)
    }
  }

  private func contactRow(_ contact: ContactSummary) -> some View {
    let participant = draft.participant(forContactIdentifier: contact.identifier)
    let avatarData = participant?.avatarData ?? contactModel.avatars[contact.identifier]

    return Button {
      if let participant {
        removeParticipant(participant.id)
      } else {
        Task {
          guard let person = await peopleModel.include(contact) else { return }
          let avatar = await contactModel.avatar(for: contact.identifier)
          draft.addPerson(person, avatarData: avatar)
          haptic.play(.selection)
        }
      }
    } label: {
      HStack(spacing: 12) {
        PersonAvatarView(name: contact.displayName, imageData: avatarData)
        Text(contact.displayName)
          .foregroundStyle(.primary)
        Spacer()
        if participant != nil {
          Image(systemName: "checkmark")
            .fontWeight(.semibold)
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .task(id: contact.identifier) {
      let avatar = await contactModel.avatar(for: contact.identifier)
      if draft.participant(forContactIdentifier: contact.identifier) != nil {
        draft.updateAvatar(avatar, forContactIdentifier: contact.identifier)
      }
    }
  }

  private func removeParticipant(_ id: ReceiptParticipant.ID) {
    draft.removeParticipant(id: id)
    haptic.play(.selection)
  }

  private func load() async {
    async let contacts: Void = contactModel.load()
    async let people: Void = peopleModel.load(receiptStorage: receiptStorage)
    _ = await (contacts, people)
  }

  private func avatar(for identifier: String?) async -> Data? {
    guard let identifier else { return nil }
    return await contactModel.avatar(for: identifier)
  }

  private func addResolvedContacts(_ identifiers: [String]) async {
    let contacts = await contactModel.resolveContacts(identifiers: identifiers)
    var didAdd = false
    for contact in contacts {
      guard let person = await peopleModel.include(contact) else { continue }
      let avatar = await contactModel.avatar(for: contact.identifier)
      draft.addPerson(person, avatarData: avatar)
      didAdd = true
    }
    if didAdd {
      haptic.play(.selection)
    }
  }
}

private struct NewPersonView: View {
  let onAdd: (String) -> Void
  @State private var name = ""
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        TextField("Name", text: $name)
          .textContentType(.name)
          .submitLabel(.done)
          .onSubmit(addPerson)
      }
      .navigationTitle("New Person")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add", action: addPerson)
            .disabled(trimmedName.isEmpty)
        }
      }
    }
    .presentationDetents([.medium])
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func addPerson() {
    guard !trimmedName.isEmpty else { return }
    onAdd(trimmedName)
    dismiss()
  }
}
