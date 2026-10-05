import ContactsUI
import SwiftUI

/// Explains why contacts can't be listed, and links to Settings unless the device restricts access.
struct ContactsUnavailableSection: View {
  let authorization: ContactAuthorization
  let settingsMessage: LocalizedStringKey
  @Environment(\.openURL) private var openURL

  var body: some View {
    Section("Contacts") {
      if authorization == .restricted {
        Text("Contacts are unavailable because this device restricts access.")
          .foregroundStyle(.secondary)
      } else {
        Text(settingsMessage)
          .foregroundStyle(.secondary)
        Button("Open Settings") {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          openURL(url)
        }
      }
    }
  }
}

/// With limited access, offers the contact access picker and a button that grants access to
/// contacts matching the search.
struct LimitedContactAccessRows: View {
  let model: PeoplePickerModel
  let onGrant: ([String]) -> Void

  var body: some View {
    if model.authorization == .limited {
      Button("Choose More Contacts", systemImage: "person.crop.circle.badge.plus") {
        model.isContactAccessPickerPresented = true
      }

      if !model.searchQuery.isEmpty {
        ContactAccessButton(queryString: model.searchText) { onGrant($0) }
      }
    }
  }
}
