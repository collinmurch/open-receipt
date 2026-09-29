import Foundation
import Observation

/// Contact photos for the screen that shows them. Each photo is fetched the first time it is
/// asked for and kept after that.
@MainActor
@Observable
final class ContactAvatars {
  private var images: [String: Data] = [:]
  @ObservationIgnored private var fetchedIdentifiers: Set<String> = []

  subscript(_ identifier: String) -> Data? {
    images[identifier]
  }

  func avatar(for identifier: String, using client: ContactClient) async -> Data? {
    if fetchedIdentifiers.contains(identifier) { return images[identifier] }
    guard client.authorizationStatus().canReadContacts else { return nil }
    do {
      let avatar = try await client.fetchAvatar(identifier)
      fetchedIdentifiers.insert(identifier)
      images[identifier] = avatar
      return avatar
    } catch {
      return nil
    }
  }
}
