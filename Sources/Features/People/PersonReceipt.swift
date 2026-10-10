import Foundation

/// A receipt a saved person is on, with what they owe on it.
struct PersonReceipt: Identifiable, Sendable {
  let summary: ReceiptSummary
  let document: ReceiptDocument
  /// The person's share, or `nil` while unassigned items keep it from being final.
  let owed: Double?
  let currency: String

  var id: ReceiptSummary.ID { summary.id }

  /// The receipt as `person` is on it, or `nil` when they aren't on it. Participants without a
  /// saved person are matched against `people`.
  static func make(
    summary: ReceiptSummary,
    document: ReceiptDocument,
    person: Person,
    people: [Person]
  ) -> PersonReceipt? {
    guard let split = document.split,
      split.hasUnlinkedPeople || split.personIDs.contains(person.id),
      let state = try? ReceiptDraftPersistenceState(document: document)
    else { return nil }
    let input = state.splitInput
    let calculation = ReceiptSplitCalculator.calculate(input)
    guard
      let share = calculation.participantShares.first(where: {
        !$0.participant.source.isCurrentUser
          && ReceiptPersonResolver.person(for: $0.participant, in: people)?.id == person.id
      })
    else { return nil }
    return PersonReceipt(
      summary: summary,
      document: document,
      owed: calculation.unassignedItemCount == 0 ? share.total : nil,
      currency: input.currency)
  }

  /// The read receipts in `summaries` that `person` is on, in the same order. Only receipts the
  /// summaries say they may be on are loaded, and their splits are worked out off the main actor.
  static func load(
    for person: Person,
    in summaries: [ReceiptSummary],
    people: [Person],
    storage: ReceiptStorageClient
  ) async -> [PersonReceipt] {
    var receipts: [PersonReceipt] = []
    for summary in summaries
    where summary.recognitionStatus == .succeeded && !summary.isUnavailable
      && summary.mayInclude(person)
    {
      guard let document = try? await storage.load(summary.id),
        let receipt = make(summary: summary, document: document, person: person, people: people)
      else { continue }
      receipts.append(receipt)
    }
    return receipts
  }
}
