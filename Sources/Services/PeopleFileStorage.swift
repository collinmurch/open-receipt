import Foundation

actor PeopleFileStorage {
  static let live = PeopleFileStorage()

  private let fileManager = FileManager.default
  private let rootOverride: URL?
  private var cachedDocumentURL: URL?

  init(rootURL: URL? = nil) {
    rootOverride = rootURL
  }

  func list() throws -> [Person] {
    try load().people.sorted(by: Person.sortsBefore)
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
      venmo.recipient.value =
        venmo.recipient.kind == .username
        ? Person.Venmo.normalizedUsername(venmo.recipient.value)
        : venmo.recipient.value.trimmingCharacters(in: .whitespacesAndNewlines)
      venmo.customUsername = venmo.customUsername.flatMap { username in
        let normalized = Person.Venmo.normalizedUsername(username)
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

  private func load() throws -> PeopleDocument {
    let url = try documentURL()
    guard fileManager.fileExists(atPath: url.path) else { return PeopleDocument() }
    let data = try Data(contentsOf: url)
    let document = try Self.decoder.decode(PeopleDocument.self, from: data)
    guard document.schemaVersion == PeopleDocument.currentSchemaVersion else {
      throw PeopleStorageError.unsupportedSchemaVersion(document.schemaVersion)
    }
    return document
  }

  private func write(_ document: PeopleDocument) throws {
    let data = try Self.encoder.encode(document)
    let url = try documentURL()
    try data.write(to: url, options: .atomic)
    try fileManager.protectItem(at: url)
  }

  private func documentURL() throws -> URL {
    if let cachedDocumentURL { return cachedDocumentURL }
    let root = try rootOverride ?? fileManager.openReceiptDirectory("People")
    try fileManager.createProtectedDirectory(at: root)
    let documentURL = root.appending(path: "people.json")
    cachedDocumentURL = documentURL
    return documentURL
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

struct PeopleDocument: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 3

  var schemaVersion = currentSchemaVersion
  var people: [Person] = []
  var owner: ReceiptOwner?
}
