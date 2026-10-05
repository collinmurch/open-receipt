import SwiftUI

struct PeopleStorageClient: Sendable {
  var list: @Sendable () async throws -> [Person]
  var include: @Sendable (Person.ID?, String, String?, Date) async throws -> Person
  var save: @Sendable (Person) async throws -> Person
  var delete: @Sendable (Person.ID) async throws -> Void
  var owner: @Sendable () async throws -> ReceiptOwner?
  var setOwner: @Sendable (ReceiptOwner?) async throws -> Void
  /// Stores the owner only when none is stored yet, and returns the stored owner.
  var adoptOwner: @Sendable (ReceiptOwner) async throws -> ReceiptOwner

  static let live = PeopleStorageClient.files(.live)

  /// A client that stores people in `storage`.
  static func files(_ storage: PeopleFileStorage) -> PeopleStorageClient {
    PeopleStorageClient(
      list: { try await storage.list() },
      include: {
        try await storage.include(id: $0, displayName: $1, contactIdentifier: $2, at: $3)
      },
      save: { try await storage.save($0) },
      delete: { try await storage.delete(id: $0) },
      owner: { try await storage.owner() },
      setOwner: { try await storage.setOwner($0) },
      adoptOwner: { try await storage.adoptOwner($0) })
  }
}

extension EnvironmentValues {
  @Entry var peopleStorageClient = PeopleStorageClient.live
}
