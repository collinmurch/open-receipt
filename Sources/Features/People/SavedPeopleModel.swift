import SwiftUI

@MainActor
@Observable
final class SavedPeopleModel {
  private(set) var people: [Person] = []
  private(set) var owner: ReceiptOwner?
  /// True only during the first load, so returning to a screen keeps showing what it had.
  private(set) var isLoading = false
  var errorDescription: String?

  private let storage: PeopleStorageClient
  @ObservationIgnored private var hasLoaded = false

  init(storage: PeopleStorageClient) {
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
    return person.adopt(contact.paymentDefaults(for: person)) ? await save(person) : person
  }

  func include(name: String) async -> Person? {
    let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !displayName.isEmpty else { return nil }
    return await include(id: nil, displayName: displayName, contactIdentifier: nil)
  }

  /// Replaces the stored owner that new receipts start with.
  func setOwner(_ owner: ReceiptOwner?) async {
    do {
      try await storage.setOwner(owner)
      self.owner = owner
      errorDescription = nil
    } catch {
      errorDescription = error.localizedDescription
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

  /// Saves the payment methods each person's contact suggests for those they haven't set.
  func adoptContactPaymentDefaults(from contactClient: ContactClient) async {
    let defaults = await contactClient.defaultPaymentMethods(for: people)
    for var person in people {
      guard let personDefaults = defaults[person.id], person.adopt(personDefaults) else {
        continue
      }
      await save(person)
    }
  }

  @discardableResult
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
      withAnimation(.smooth(duration: 0.3)) {
        people.removeAll { $0.id == person.id }
      }
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
    contactIdentifier: String?
  ) async -> Person? {
    do {
      let person = try await storage.include(id, displayName, contactIdentifier, Date())
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
    people.sort(by: Person.sortsBefore)
  }
}
