import Foundation

/// A receipt a saved person is on, with what they owe on it.
struct PersonReceipt: Identifiable {
  let summary: ReceiptSummary
  let document: ReceiptDocument
  /// The person's share, or `nil` while unassigned items keep it from being final.
  let owed: Double?
  let currency: String

  var id: ReceiptSummary.ID { summary.id }

  /// The receipt as `person` is on it, or `nil` when they aren't on it. Legacy participants
  /// without a person are matched against `people`.
  @MainActor
  static func make(
    summary: ReceiptSummary,
    document: ReceiptDocument,
    person: Person,
    people: [Person]
  ) -> PersonReceipt? {
    // A participant saved with a person resolves only to that person, so the split is worked out
    // only for receipts that have this person or a legacy participant to match by contact or name.
    guard
      document.split?.participants.contains(where: {
        $0.personID == nil || $0.personID == person.id
      }) == true,
      let draft = try? ReceiptDraft(document: document)
    else { return nil }
    let calculation = draft.splitCalculation
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
      currency: draft.displayCurrency)
  }

  /// The read receipts in `summaries` that `person` is on, in the same order.
  @MainActor
  static func load(
    for person: Person,
    in summaries: [ReceiptSummary],
    people: [Person],
    storage: ReceiptStorageClient
  ) async -> [PersonReceipt] {
    var receipts: [PersonReceipt] = []
    for summary in summaries
    where summary.recognitionStatus == .succeeded && !summary.isUnavailable {
      guard let document = try? await storage.load(summary.id),
        let receipt = make(summary: summary, document: document, person: person, people: people)
      else { continue }
      receipts.append(receipt)
    }
    return receipts
  }
}
