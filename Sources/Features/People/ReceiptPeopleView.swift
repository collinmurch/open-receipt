import Contacts
import ContactsUI
import SwiftUI

struct ReceiptPeopleView: View {
  private static let participantAnimation = Animation.smooth(duration: 0.25)

  let draft: ReceiptDraft
  private let contactClient: ContactClient
  @State private var contactModel: PeoplePickerModel
  @State private var peopleModel: SavedPeopleModel
  @State private var isNewPersonPresented = false
  @State private var haptic = HapticEvent()
  @Environment(\.dismiss) private var dismiss

  init(
    draft: ReceiptDraft,
    contactClient: ContactClient,
    peopleStorage: PeopleStorageClient
  ) {
    self.draft = draft
    self.contactClient = contactClient
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
            LoadingRow(title: "Loading people")
          }
        } else if contactModel.canReadContacts {
          contactsSection
        } else {
          ContactsUnavailableSection(
            authorization: contactModel.authorization,
            settingsMessage: "Allow Contacts access in Settings to add people from your contacts.")
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
        ToolbarItem(placement: .topBarLeading) {
          Button(role: .close) { dismiss() }
        }
      }
      .sheet(isPresented: $isNewPersonPresented) {
        NewPersonView { name in
          Task {
            guard let person = await peopleModel.include(name: name) else { return }
            addToDraft(person)
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
      setDraftOwner(nil)
      return
    }
    let owner = ReceiptOwner(contact)
    Task {
      let avatar = await contactModel.avatar(for: contact.identifier)
      setDraftOwner(owner, avatarData: avatar)
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
              addToDraft(included, avatarData: avatar)
              haptic.play(.selection)
            }
          }
        } label: {
          PersonSelectionRow(
            name: person.displayName,
            avatarData: person.contactIdentifier.flatMap { contactModel.avatars[$0] },
            isSelected: participant != nil)
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
      LimitedContactAccessRows(model: contactModel) { identifiers in
        Task { await addResolvedContacts(identifiers) }
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
          addToDraft(person, avatarData: avatar)
          haptic.play(.selection)
        }
      }
    } label: {
      PersonSelectionRow(
        name: contact.displayName,
        avatarData: avatarData,
        isSelected: participant != nil)
    }
    .buttonStyle(.plain)
    .task(id: contact.identifier) {
      let avatar = await contactModel.avatar(for: contact.identifier)
      if draft.participant(forContactIdentifier: contact.identifier) != nil {
        draft.updateAvatar(avatar, forContactIdentifier: contact.identifier)
      }
    }
  }

  private func addToDraft(_ person: Person, avatarData: Data? = nil) {
    withAnimation(Self.participantAnimation) {
      _ = draft.addPerson(person, avatarData: avatarData)
    }
  }

  private func removeParticipant(_ id: ReceiptParticipant.ID) {
    withAnimation(Self.participantAnimation) {
      draft.removeParticipant(id: id)
    }
    haptic.play(.selection)
  }

  private func setDraftOwner(_ owner: ReceiptOwner?, avatarData: Data? = nil) {
    withAnimation(Self.participantAnimation) {
      draft.setOwner(owner, avatarData: avatarData)
    }
    haptic.play(.selection)
  }

  private func load() async {
    async let contacts: Void = contactModel.load()
    async let people: Void = peopleModel.load()
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
      addToDraft(person, avatarData: avatar)
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
          Button(role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add", systemImage: "checkmark", role: .confirm, action: addPerson)
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
