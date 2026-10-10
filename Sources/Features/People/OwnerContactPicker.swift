import ContactsUI
import SwiftUI

/// Lists contacts so the person using the app can choose their own card. Choosing "Me" clears it.
struct OwnerContactPicker: View {
  let selectedIdentifier: String?
  let onSelect: (ContactSummary?) -> Void
  @State private var model: PeoplePickerModel
  @Environment(\.dismiss) private var dismiss

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
          PersonSelectionRow(
            name: ReceiptParticipant.defaultCurrentUserName,
            contactIdentifier: nil,
            isSelected: selectedIdentifier == nil)
        }
        .buttonStyle(.plain)
      } footer: {
        Text("Your contact’s name and photo appear on receipts in place of “Me”.")
      }

      if model.isLoading {
        Section {
          LoadingRow(title: "Loading contacts")
        }
      } else if model.canReadContacts {
        contactsSection
      } else {
        ContactsUnavailableSection(
          authorization: model.authorization,
          settingsMessage: "Allow Contacts access in Settings to choose your contact.")
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
      LimitedContactAccessRows(model: model) { identifiers in
        Task { await selectResolvedContact(identifiers) }
      }

      if model.filteredContacts.isEmpty {
        Text("No matching contacts")
          .foregroundStyle(.secondary)
      } else {
        ForEach(model.filteredContacts) { contact in
          Button {
            select(contact)
          } label: {
            PersonSelectionRow(
              name: contact.displayName,
              contactIdentifier: contact.identifier,
              isSelected: contact.identifier == selectedIdentifier)
          }
          .buttonStyle(.plain)
        }
      }
    }
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
