import Foundation
import Observation

/// The saved people behind a receipt's payment requests, with payment methods filled in from
/// their contacts.
@MainActor
@Observable
final class ReceiptRequestPeople {
  private(set) var peopleByID: [Person.ID: Person] = [:]
  var errorDescription: String?
  @ObservationIgnored private var hasLoaded = false

  func load(
    receiptStorage: ReceiptStorageClient,
    peopleStorage: PeopleStorageClient,
    contactClient: ContactClient
  ) async {
    guard !hasLoaded else { return }
    do {
      let snapshots = try await receiptStorage.listPersonSnapshots()
      try Task.checkCancellation()
      try await peopleStorage.importReceiptParticipants(snapshots)
      try Task.checkCancellation()
      var people = try await peopleStorage.list()
      try Task.checkCancellation()
      let defaults = await contactClient.defaultPaymentMethods(for: people)
      for index in people.indices {
        try Task.checkCancellation()
        guard let paymentDefaults = defaults[people[index].id],
          people[index].adopt(paymentDefaults)
        else { continue }
        people[index] = try await peopleStorage.save(people[index])
      }
      try Task.checkCancellation()
      peopleByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
      hasLoaded = true
    } catch is CancellationError {
      return
    } catch {
      errorDescription = error.localizedDescription
    }
  }

  func save(_ person: Person, storage: PeopleStorageClient) async -> Person? {
    do {
      let saved = try await storage.save(person)
      peopleByID[saved.id] = saved
      errorDescription = nil
      return saved
    } catch {
      errorDescription = error.localizedDescription
      return nil
    }
  }

  func delete(_ person: Person, storage: PeopleStorageClient) async -> Bool {
    do {
      try await storage.delete(person.id)
      peopleByID[person.id] = nil
      errorDescription = nil
      return true
    } catch {
      errorDescription = error.localizedDescription
      return false
    }
  }
}
