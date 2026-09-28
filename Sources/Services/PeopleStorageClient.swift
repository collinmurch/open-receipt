import Foundation
import SwiftUI

struct PeopleStorageClient: Sendable {
  var list: @Sendable () async throws -> [Person]
  var include: @Sendable (Person.ID?, String, String?, Date) async throws -> Person
  var save: @Sendable (Person) async throws -> Person
  var delete: @Sendable (Person.ID) async throws -> Void
  var importReceiptParticipants: @Sendable ([ReceiptPersonSnapshot]) async throws -> Void
  var owner: @Sendable () async throws -> ReceiptOwner? = { nil }
  var setOwner: @Sendable (ReceiptOwner?) async throws -> Void = { _ in }
  /// Stores the owner only when none is stored yet, and returns the stored owner.
  var adoptOwner: @Sendable (ReceiptOwner) async throws -> ReceiptOwner = { $0 }

  static let live: PeopleStorageClient = {
    let storage = PeopleFileStorage.live
    return PeopleStorageClient(
      list: { try await storage.list() },
      include: {
        try await storage.include(id: $0, displayName: $1, contactIdentifier: $2, at: $3)
      },
      save: { try await storage.save($0) },
      delete: { try await storage.delete(id: $0) },
      importReceiptParticipants: { try await storage.importReceiptParticipants($0) },
      owner: { try await storage.owner() },
      setOwner: { try await storage.setOwner($0) },
      adoptOwner: { try await storage.adoptOwner($0) })
  }()
}

actor PeopleFileStorage {
  static let live = PeopleFileStorage()

  private let fileManager: FileManager
  private let rootOverride: URL?

  init(fileManager: FileManager = .default, rootURL: URL? = nil) {
    self.fileManager = fileManager
    rootOverride = rootURL
  }

  func list() throws -> [Person] {
    try load().people.sorted(by: Self.sortPeople)
  }

  func include(
    id: Person.ID?,
    displayName: String,
    contactIdentifier: String?,
    at date: Date
  ) throws -> Person {
    var document = try load()
    let index = document.people.firstIndex { person in
      if let id, person.id == id { return true }
      guard let contactIdentifier else { return false }
      return person.contactIdentifier == contactIdentifier
    }

    if let index {
      document.people[index].displayName = displayName
      document.people[index].contactIdentifier =
        contactIdentifier ?? document.people[index].contactIdentifier
      document.people[index].lastIncludedAt = max(
        document.people[index].lastIncludedAt,
        date)
      document.people[index].updatedAt = date
      let person = document.people[index]
      try write(document)
      return person
    }

    let person = Person(
      id: id ?? UUID(),
      createdAt: date,
      updatedAt: date,
      lastIncludedAt: date,
      displayName: displayName,
      contactIdentifier: contactIdentifier,
      paymentMethods: .init())
    document.people.append(person)
    try write(document)
    return person
  }

  func save(_ person: Person) throws -> Person {
    var document = try load()
    var person = person
    person.displayName = person.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !person.displayName.isEmpty else { throw PeopleStorageError.emptyDisplayName }

    if var venmo = person.paymentMethods.venmo {
      venmo.recipient.value = Self.normalize(
        venmo.recipient.value,
        as: venmo.recipient.kind)
      venmo.customUsername = venmo.customUsername.flatMap { username in
        let normalized = Self.normalize(username, as: .username)
        return normalized.isEmpty ? nil : normalized
      }
      person.paymentMethods.venmo = venmo.recipient.value.isEmpty ? nil : venmo
    }
    if var cashApp = person.paymentMethods.cashApp {
      cashApp.cashtag = Person.CashApp.normalizedCashtag(cashApp.cashtag)
      person.paymentMethods.cashApp = cashApp.cashtag.isEmpty ? nil : cashApp
    }
    if var iMessage = person.paymentMethods.iMessage {
      iMessage.recipient.value = iMessage.recipient.value.trimmingCharacters(
        in: .whitespacesAndNewlines)
      person.paymentMethods.iMessage = iMessage.recipient.value.isEmpty ? nil : iMessage
    }
    person.updatedAt = Date()

    guard let index = document.people.firstIndex(where: { $0.id == person.id }) else {
      throw PeopleStorageError.personNotFound(person.id)
    }
    document.people[index] = person
    try write(document)
    return person
  }

  func delete(id: Person.ID) throws {
    var document = try load()
    document.people.removeAll { $0.id == id }
    try write(document)
  }

  func owner() throws -> ReceiptOwner? {
    try load().owner
  }

  func setOwner(_ owner: ReceiptOwner?) throws {
    var document = try load()
    document.owner = owner
    try write(document)
  }

  func adoptOwner(_ owner: ReceiptOwner) throws -> ReceiptOwner {
    var document = try load()
    if let existing = document.owner { return existing }
    document.owner = owner
    try write(document)
    return owner
  }

  func importReceiptParticipants(_ snapshots: [ReceiptPersonSnapshot]) throws {
    var document = try load()
    guard !document.didImportReceiptParticipants else { return }

    for snapshot in snapshots.sorted(by: { $0.includedAt < $1.includedAt }) {
      let index = document.people.firstIndex { person in
        if let personID = snapshot.personID, person.id == personID { return true }
        guard let contactIdentifier = snapshot.contactIdentifier else { return false }
        return person.contactIdentifier == contactIdentifier
      }

      if let index {
        if document.people[index].lastIncludedAt <= snapshot.includedAt {
          document.people[index].displayName = snapshot.displayName
        }
        document.people[index].lastIncludedAt = max(
          document.people[index].lastIncludedAt,
          snapshot.includedAt)
        document.people[index].updatedAt = max(
          document.people[index].updatedAt, snapshot.includedAt)
        continue
      }

      document.people.append(
        Person(
          id: snapshot.personID ?? UUID(),
          createdAt: snapshot.includedAt,
          updatedAt: snapshot.includedAt,
          lastIncludedAt: snapshot.includedAt,
          displayName: snapshot.displayName,
          contactIdentifier: snapshot.contactIdentifier,
          paymentMethods: .init()))
    }

    document.didImportReceiptParticipants = true
    try write(document)
  }

  private func load() throws -> PeopleDocument {
    let url = try documentURL()
    guard fileManager.fileExists(atPath: url.path) else {
      return PeopleDocument(
        schemaVersion: PeopleDocument.currentSchemaVersion,
        didImportReceiptParticipants: false,
        people: [])
    }
    let data = try Data(contentsOf: url)
    var document = try Self.decoder.decode(PeopleDocument.self, from: data)
    guard (1...PeopleDocument.currentSchemaVersion).contains(document.schemaVersion) else {
      throw PeopleStorageError.unsupportedSchemaVersion(document.schemaVersion)
    }
    document.schemaVersion = PeopleDocument.currentSchemaVersion
    return document
  }

  private func write(_ document: PeopleDocument) throws {
    let data = try Self.encoder.encode(document)
    let url = try documentURL()
    try data.write(to: url, options: .atomic)
    try fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path)
  }

  private func documentURL() throws -> URL {
    let root: URL
    if let rootOverride {
      root = rootOverride
    } else {
      let applicationSupport = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true)
      root =
        applicationSupport
        .appending(path: "OpenReceipt", directoryHint: .isDirectory)
        .appending(path: "People", directoryHint: .isDirectory)
    }
    try fileManager.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    return root.appending(path: "people.json")
  }

  private static func sortPeople(_ lhs: Person, _ rhs: Person) -> Bool {
    if lhs.lastIncludedAt != rhs.lastIncludedAt {
      return lhs.lastIncludedAt > rhs.lastIncludedAt
    }
    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
  }

  private static func normalize(
    _ value: String,
    as kind: Person.Venmo.Recipient.Kind
  ) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard kind == .username else { return trimmed }
    return String(trimmed.trimmingPrefix("@"))
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

enum PeopleStorageError: Error, LocalizedError, Equatable {
  case emptyDisplayName
  case personNotFound(Person.ID)
  case unsupportedSchemaVersion(Int)

  var errorDescription: String? {
    switch self {
    case .emptyDisplayName:
      "A person must have a name."
    case .personNotFound:
      "The saved person could not be found."
    case .unsupportedSchemaVersion(let version):
      "People schema version \(version) is not supported."
    }
  }
}

private struct PeopleStorageClientKey: EnvironmentKey {
  static let defaultValue = PeopleStorageClient.live
}

extension EnvironmentValues {
  var peopleStorageClient: PeopleStorageClient {
    get { self[PeopleStorageClientKey.self] }
    set { self[PeopleStorageClientKey.self] = newValue }
  }
}
