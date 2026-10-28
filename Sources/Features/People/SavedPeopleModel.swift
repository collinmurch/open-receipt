import SwiftUI

@Observable
final class SavedPeopleModel {
  private(set) var people: [Person] = []
  private(set) var owner: ReceiptOwner?
  /// True only during the first load, so returning to a screen keeps showing what it had.
  private(set) var isLoading = false
  var errorDescription: String?

  private let storage: PeopleFileStorage
  @ObservationIgnored private var hasLoaded = false

  init(storage: PeopleFileStorage) {
    self.storage = storage
  }

  func load() async {
    isLoading = !hasLoaded
    errorDescription = nil
    defer {
      isLoading = false
      hasLoaded = true
    }

    do {
      people = try await storage.list()
      owner = try await storage.owner()
    } catch {
      errorDescription = error.localizedDescription
    }
  }

  func include(_ person: Person) async -> Person? {
    await include(
      id: person.id,
      displayName: person.displayName,
      contactIdentifier: person.contactIdentifier)
  }

  func include(_ contact: ContactSummary) async -> Person? {
    guard
      var person = await include(
        id: nil,
        displayName: contact.displayName,
        contactIdentifier: contact.identifier)
    else { return nil }
    return person.paymentMethods.adoptRecipients(of: contact) ? await save(person) : person
  }

  func include(name: String) async -> Person? {
    let displayName = name.trimmed
    guard !displayName.isEmpty else { return nil }
    return await include(id: nil, displayName: displayName, contactIdentifier: nil)
  }

  /// Replaces the stored owner that new receipts start with.
  func setOwner(_ owner: ReceiptOwner?) async {
    guard await attempt({ try await storage.setOwner(owner) }) != nil else { return }
    self.owner = owner
  }

  /// Stores `owner` only when no owner is stored yet.
  func adoptOwner(_ owner: ReceiptOwner) async {
    guard let adopted = await attempt({ try await storage.adoptOwner(owner) }) else { return }
    self.owner = adopted
  }

  /// Saves the payment methods each person's contact suggests for those they haven't set.
  func adoptContactPaymentDefaults(from contactClient: ContactClient) async {
    let unset = people.filter {
      $0.paymentMethods.venmo == nil || $0.paymentMethods.iMessage == nil
    }
    let contacts = await contactClient.contacts(
      withIdentifiers: unset.compactMap(\.contactIdentifier))
    for var person in unset {
      guard let contact = person.contactIdentifier.flatMap({ contacts[$0] }),
        person.paymentMethods.adoptRecipients(of: contact)
      else { continue }
      await save(person)
    }
  }

  @discardableResult
  func save(_ person: Person) async -> Person? {
    guard let saved = await attempt({ try await storage.save(person) }) else { return nil }
    replace(saved)
    return saved
  }

  func delete(_ person: Person) async -> Bool {
    guard await attempt({ try await storage.delete(id: person.id) }) != nil else { return false }
    withAnimation(.smooth(duration: 0.3)) {
      people.removeAll { $0.id == person.id }
    }
    return true
  }

  private func include(
    id: Person.ID?,
    displayName: String,
    contactIdentifier: String?
  ) async -> Person? {
    guard
      let person = await attempt({
        try await storage.include(
          id: id, displayName: displayName, contactIdentifier: contactIdentifier, at: Date())
      })
    else { return nil }
    replace(person)
    return person
  }

  /// Runs `operation`, showing its error when it fails and clearing the last one when it succeeds.
  private func attempt<Value>(_ operation: () async throws -> Value) async -> Value? {
    do {
      let value = try await operation()
      errorDescription = nil
      return value
    } catch {
      errorDescription = error.localizedDescription
      return nil
    }
  }

  private func replace(_ person: Person) {
    people.removeAll { $0.id == person.id }
    people.append(person)
    people.sort(by: Person.sortsBefore)
  }
}
