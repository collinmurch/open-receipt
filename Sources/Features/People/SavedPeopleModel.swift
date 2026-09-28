import Foundation
import Observation

@MainActor
@Observable
final class SavedPeopleModel {
  private(set) var people: [Person] = []
  private(set) var owner: ReceiptOwner?
  private(set) var isLoading = false
  var errorDescription: String?

  @ObservationIgnored private let storage: PeopleStorageClient

  init(storage: PeopleStorageClient) {
    self.storage = storage
  }

  func load(receiptStorage: ReceiptStorageClient) async {
    isLoading = true
    errorDescription = nil
    defer { isLoading = false }

    do {
      let snapshots = try await receiptStorage.listPersonSnapshots()
      try await storage.importReceiptParticipants(snapshots)
      people = try await storage.list()
      owner = try await storage.owner()
    } catch {
      errorDescription = error.localizedDescription
    }
  }

  func include(_ person: Person, at date: Date = Date()) async -> Person? {
    await include(
      id: person.id,
      displayName: person.displayName,
      contactIdentifier: person.contactIdentifier,
      at: date)
  }

  func include(_ contact: ContactSummary, at date: Date = Date()) async -> Person? {
    guard
      var person = await include(
        id: nil,
        displayName: contact.displayName,
        contactIdentifier: contact.identifier,
        at: date)
    else { return nil }
    var didChange = false
    if person.paymentMethods.venmo == nil, let recipient = contact.defaultVenmoRecipient {
      person.paymentMethods.venmo = .init(recipient: recipient)
      didChange = true
    }
    if person.paymentMethods.iMessage == nil, let recipient = contact.defaultIMessageRecipient {
      person.paymentMethods.iMessage = .init(recipient: recipient)
      didChange = true
    }
    return didChange ? await save(person) : person
  }

  func include(name: String, at date: Date = Date()) async -> Person? {
    let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !displayName.isEmpty else { return nil }
    return await include(
      id: nil,
      displayName: displayName,
      contactIdentifier: nil,
      at: date)
  }

  /// Replaces the stored owner that new receipts start with.
  func setOwner(_ owner: ReceiptOwner?) async -> Bool {
    do {
      try await storage.setOwner(owner)
      self.owner = owner
      errorDescription = nil
      return true
    } catch {
      errorDescription = error.localizedDescription
      return false
    }
  }

  /// Stores `owner` only when no owner is stored yet.
  func adoptOwner(_ owner: ReceiptOwner) async {
    do {
      self.owner = try await storage.adoptOwner(owner)
      errorDescription = nil
    } catch {
      errorDescription = error.localizedDescription
    }
  }

  func save(_ person: Person) async -> Person? {
    do {
      let saved = try await storage.save(person)
      replace(saved)
      errorDescription = nil
      return saved
    } catch {
      errorDescription = error.localizedDescription
      return nil
    }
  }

  func delete(_ person: Person) async -> Bool {
    do {
      try await storage.delete(person.id)
      people.removeAll { $0.id == person.id }
      errorDescription = nil
      return true
    } catch {
      errorDescription = error.localizedDescription
      return false
    }
  }

  private func include(
    id: Person.ID?,
    displayName: String,
    contactIdentifier: String?,
    at date: Date
  ) async -> Person? {
    do {
      let person = try await storage.include(id, displayName, contactIdentifier, date)
      replace(person)
      errorDescription = nil
      return person
    } catch {
      errorDescription = error.localizedDescription
      return nil
    }
  }

  private func replace(_ person: Person) {
    people.removeAll { $0.id == person.id }
    people.append(person)
    people.sort {
      if $0.lastIncludedAt != $1.lastIncludedAt {
        return $0.lastIncludedAt > $1.lastIncludedAt
      }
      return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
    }
  }
}
