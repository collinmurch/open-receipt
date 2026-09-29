import Foundation
import Observation

@MainActor
@Observable
final class PeoplePickerModel {
  private(set) var authorization: ContactAuthorization = .notDetermined
  private(set) var contacts: [ContactSummary] = []
  private(set) var avatars: [String: Data] = [:]
  private var loadedAvatarIdentifiers: Set<String> = []
  private(set) var isLoading = false
  var searchText = ""
  var errorDescription: String?
  var isContactAccessPickerPresented = false

  @ObservationIgnored private let client: ContactClient

  init(client: ContactClient) {
    self.client = client
  }

  var filteredContacts: [ContactSummary] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return contacts }
    return contacts.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
  }

  var canReadContacts: Bool {
    authorization.canReadContacts
  }

  func load() async {
    isLoading = true
    errorDescription = nil
    defer { isLoading = false }

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
    if loadedAvatarIdentifiers.contains(identifier) { return avatars[identifier] }
    do {
      let avatar = try await client.fetchAvatar(identifier)
      loadedAvatarIdentifiers.insert(identifier)
      if let avatar {
        avatars[identifier] = avatar
      }
      return avatar
    } catch {
      return nil
    }
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
