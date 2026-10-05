import Foundation
import Observation

@MainActor
@Observable
final class PeoplePickerModel {
  private(set) var authorization: ContactAuthorization = .notDetermined
  private(set) var contacts: [ContactSummary] = []
  /// True only during the first load, so returning to a screen keeps showing what it had.
  private(set) var isLoading = false
  var searchText = ""
  var errorDescription: String?
  var isContactAccessPickerPresented = false
  let avatars = ContactAvatars()

  private let client: ContactClient
  @ObservationIgnored private var hasLoaded = false

  init(client: ContactClient) {
    self.client = client
  }

  /// `searchText` without surrounding whitespace.
  var searchQuery: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var filteredContacts: [ContactSummary] {
    let query = searchQuery
    guard !query.isEmpty else { return contacts }
    return contacts.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
  }

  var canReadContacts: Bool {
    authorization.canReadContacts
  }

  func load() async {
    isLoading = !hasLoaded
    errorDescription = nil
    defer {
      isLoading = false
      hasLoaded = true
    }

    do {
      authorization = client.authorizationStatus()
      if authorization == .notDetermined {
        authorization = try await client.requestAccess()
      }
      if canReadContacts {
        contacts = try await client.fetchContacts(nil)
      } else {
        contacts = []
      }
    } catch {
      authorization = client.authorizationStatus()
      errorDescription = error.localizedDescription
    }
  }

  func reload() async {
    authorization = client.authorizationStatus()
    guard canReadContacts else {
      contacts = []
      return
    }
    do {
      contacts = try await client.fetchContacts(nil)
      errorDescription = nil
    } catch {
      errorDescription = error.localizedDescription
    }
  }

  func resolveContacts(identifiers: [String]) async -> [ContactSummary] {
    guard !identifiers.isEmpty else { return [] }
    do {
      let resolved = try await client.fetchContacts(identifiers)
      merge(resolved)
      errorDescription = nil
      return resolved
    } catch {
      errorDescription = error.localizedDescription
      return []
    }
  }

  func avatar(for identifier: String) async -> Data? {
    await avatars.avatar(for: identifier, using: client)
  }

  private func merge(_ newContacts: [ContactSummary]) {
    var contactsByIdentifier = Dictionary(
      uniqueKeysWithValues: contacts.map { ($0.identifier, $0) })
    for contact in newContacts {
      contactsByIdentifier[contact.identifier] = contact
    }
    contacts = contactsByIdentifier.values.sorted {
      $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
    }
  }
}
