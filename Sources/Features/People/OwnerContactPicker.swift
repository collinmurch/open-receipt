import Contacts
import ContactsUI
import SwiftUI

/// Lists contacts so the person using the app can choose their own card. Choosing "Me" clears it.
struct OwnerContactPicker: View {
  let selectedIdentifier: String?
  let onSelect: (ContactSummary?) -> Void
  @State private var model: PeoplePickerModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL

  init(
    contactClient: ContactClient,
    selectedIdentifier: String?,
    onSelect: @escaping (ContactSummary?) -> Void
  ) {
    self.selectedIdentifier = selectedIdentifier
    self.onSelect = onSelect
    _model = State(initialValue: PeoplePickerModel(client: contactClient))
  }

  var body: some View {
    @Bindable var model = model

    List {
      Section {
        Button {
          select(nil)
        } label: {
          row(
            name: ReceiptParticipant.defaultCurrentUserName,
            avatarData: nil,
            isSelected: selectedIdentifier == nil)
        }
        .buttonStyle(.plain)
      } footer: {
        Text("Your contact’s name and photo appear on receipts in place of “Me”.")
      }

      if model.isLoading {
        Section {
          HStack {
            Spacer()
            ProgressView("Loading contacts")
            Spacer()
          }
        }
      } else if model.canReadContacts {
        contactsSection
      } else {
        unavailableContactsSection
      }
    }
    .navigationTitle("Choose Your Contact")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $model.searchText, prompt: "Search contacts")
    .contactAccessPicker(isPresented: $model.isContactAccessPickerPresented) { identifiers in
      Task { await selectResolvedContact(identifiers) }
    }
    .task { await model.load() }
  }

  private var contactsSection: some View {
    Section("Contacts") {
      if model.authorization == .limited {
        Button("Choose More Contacts", systemImage: "person.crop.circle.badge.plus") {
          model.isContactAccessPickerPresented = true
        }

        if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          ContactAccessButton(queryString: model.searchText) { identifiers in
            Task { await selectResolvedContact(identifiers) }
          }
        }
      }

      if model.filteredContacts.isEmpty {
        Text("No matching contacts")
          .foregroundStyle(.secondary)
      } else {
        ForEach(model.filteredContacts) { contact in
          Button {
            select(contact)
          } label: {
            row(
              name: contact.displayName,
              avatarData: model.avatars[contact.identifier],
              isSelected: contact.identifier == selectedIdentifier)
          }
          .buttonStyle(.plain)
          .task(id: contact.identifier) {
            _ = await model.avatar(for: contact.identifier)
          }
        }
      }
    }
  }

  private var unavailableContactsSection: some View {
    Section("Contacts") {
      if model.authorization == .restricted {
        Text("Contacts are unavailable because this device restricts access.")
          .foregroundStyle(.secondary)
      } else {
        Text("Allow Contacts access in Settings to choose your contact.")
          .foregroundStyle(.secondary)
        Button("Open Settings") {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          openURL(url)
        }
      }
    }
  }

  private func row(name: String, avatarData: Data?, isSelected: Bool) -> some View {
    HStack(spacing: 12) {
      PersonAvatarView(name: name, imageData: avatarData)
      Text(name)
        .foregroundStyle(.primary)
      Spacer()
      if isSelected {
        Image(systemName: "checkmark")
          .fontWeight(.semibold)
          .foregroundStyle(.tint)
      }
    }
    .contentShape(.rect)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func select(_ contact: ContactSummary?) {
    onSelect(contact)
    dismiss()
  }

  private func selectResolvedContact(_ identifiers: [String]) async {
    guard let contact = await model.resolveContacts(identifiers: identifiers).first else { return }
    select(contact)
  }
}

extension ReceiptOwner {
  init(_ contact: ContactSummary) {
    self.init(contactIdentifier: contact.identifier, displayName: contact.displayName)
  }
}
