import Contacts
import Observation

/// Contact photos for every screen. Each is fetched the first time it's shown and kept, and
/// fetched again after Contacts changes.
@MainActor
@Observable
final class ContactPhotos {
  private var photos: [String: Data] = [:]
  @ObservationIgnored private var requested: Set<String> = []
  @ObservationIgnored private let client: ContactClient
  @ObservationIgnored private var changes: Task<Void, Never>?

  init(client: ContactClient) {
    self.client = client
    changes = Task { [weak self] in
      for await _ in NotificationCenter.default.notifications(named: .CNContactStoreDidChange) {
        // Photos already shown stay up until their next fetch replaces them.
        self?.requested.removeAll()
      }
    }
  }

  isolated deinit {
    changes?.cancel()
  }

  subscript(_ identifier: String?) -> Data? {
    identifier.flatMap { photos[$0] }
  }

  /// Fetches the photo of the contact `identifier` names, unless it already has been.
  func load(_ identifier: String?) async {
    guard let identifier, !requested.contains(identifier),
      client.authorizationStatus().canReadContacts
    else { return }
    requested.insert(identifier)
    do {
      let photo = try await client.fetchAvatar(identifier)
      if photos[identifier] != photo { photos[identifier] = photo }
    } catch {
      requested.remove(identifier)
    }
  }
}
