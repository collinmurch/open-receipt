import XCTest

@testable import open_receipt

@MainActor
final class PersonReceiptTests: XCTestCase {
  func testOwedIsPersonsShare() throws {
    let sam = makePerson(name: "Sam")
    let draft = makeDraft()
    let participant = draft.addPerson(sam)
    draft.items[0].participantIDs = [participant.id]
    draft.items[1].participantIDs = [draft.participants[0].id]

    let receipt = try XCTUnwrap(make(draft, person: sam, people: [sam]))

    XCTAssertEqual(receipt.owed ?? 0, 6.6, accuracy: 0.001)
    XCTAssertEqual(receipt.currency, "USD")
  }

  func testOwedIsNilWhileItemsAreUnassigned() throws {
    let sam = makePerson(name: "Sam")
    let draft = makeDraft()
    let participant = draft.addPerson(sam)
    draft.items[0].participantIDs = [participant.id]

    let receipt = try XCTUnwrap(make(draft, person: sam, people: [sam]))

    XCTAssertNil(receipt.owed)
  }

  func testPersonNotOnReceiptIsLeftOut() {
    let sam = makePerson(name: "Sam")
    let alex = makePerson(name: "Alex")
    let draft = makeDraft()
    draft.addPerson(alex)

    XCTAssertNil(make(draft, person: sam, people: [sam, alex]))
  }

  func testLegacyParticipantMatchesByName() throws {
    let sam = makePerson(name: "Sam")
    let draft = makeDraft()
    draft.addManualParticipant(named: "Sam")
    var document = pendingDocument(id: draft.id).updating(from: draft)
    document.split?.participants[1].personID = nil

    XCTAssertNotNil(
      PersonReceipt.make(
        summary: makeSummary(id: draft.id),
        document: document,
        person: sam,
        people: [sam]))
  }

  func testCurrentUserIsNotMatched() {
    let owner = makePerson(name: "Alex", contactIdentifier: "me")
    let draft = makeDraft()
    draft.setOwner(ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

    XCTAssertNil(make(draft, person: owner, people: [owner]))
  }

  func testLoadSkipsUnreadAndUnavailableReceipts() async {
    let sam = makePerson(name: "Sam")
    let draft = makeDraft()
    draft.addPerson(sam)
    let document = pendingDocument(id: draft.id).updating(from: draft)
    let summaries = [
      makeSummary(id: UUID(), status: .pending),
      makeSummary(id: UUID(), isUnavailable: true),
      makeSummary(id: draft.id),
    ]

    let receipts = await PersonReceipt.load(
      for: sam,
      in: summaries,
      people: [sam],
      storage: makeStorage { _ in document })

    XCTAssertEqual(receipts.map(\.id), [draft.id])
  }

  func testLoadSkipsReceiptsThatFailToLoad() async {
    let sam = makePerson(name: "Sam")

    let receipts = await PersonReceipt.load(
      for: sam,
      in: [makeSummary(id: UUID())],
      people: [sam],
      storage: makeStorage { _ in throw TestError.loadFailed })

    XCTAssertTrue(receipts.isEmpty)
  }

  private func make(_ draft: ReceiptDraft, person: Person, people: [Person]) -> PersonReceipt? {
    PersonReceipt.make(
      summary: makeSummary(id: draft.id),
      document: pendingDocument(id: draft.id).updating(from: draft),
      person: person,
      people: people)
  }

  private func makeDraft() -> ReceiptDraft {
    ReceiptDraft(
      receipt: ParsedReceipt(
        merchantName: "Cafe",
        date: "2026-08-11",
        subtotal: 10,
        tax: 1,
        total: 11,
        currency: "USD",
        items: [
          ReceiptItem(description: "Sandwich", quantity: 1, lineTotal: 6),
          ReceiptItem(description: "Coffee", quantity: 1, lineTotal: 4),
        ]),
      backgroundStyle: .mint)
  }

  private func makePerson(name: String, contactIdentifier: String? = nil) -> Person {
    let date = Date(timeIntervalSince1970: 1)
    return Person(
      id: UUID(),
      createdAt: date,
      updatedAt: date,
      lastIncludedAt: date,
      displayName: name,
      contactIdentifier: contactIdentifier,
      paymentMethods: .init())
  }

  private func makeSummary(
    id: UUID,
    status: ReceiptDocument.Recognition.Status = .succeeded,
    isUnavailable: Bool = false
  ) -> ReceiptSummary {
    ReceiptSummary(
      id: id,
      updatedAt: Date(timeIntervalSince1970: 1),
      capturedAt: Date(timeIntervalSince1970: 1),
      backgroundStyle: .mint,
      recognitionStatus: status,
      merchantName: "Cafe",
      localDate: "2026-08-11",
      total: 11,
      currency: "USD",
      isUnavailable: isUnavailable,
      unavailableDescription: nil)
  }

  private func pendingDocument(id: UUID) -> ReceiptDocument {
    ReceiptDocument(
      schemaVersion: 1,
      id: id,
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1),
      presentation: .init(backgroundStyle: .mint),
      scan: .init(
        capturedAt: Date(timeIntervalSince1970: 1),
        source: .documentCamera,
        pages: []),
      recognition: .init(status: .pending, contractVersion: 1),
      receipt: nil,
      split: nil)
  }

  private func makeStorage(
    load: @escaping @Sendable (UUID) async throws -> ReceiptDocument
  ) -> ReceiptStorageClient {
    ReceiptStorageClient(
      create: { _, _ in throw TestError.unused },
      createBlank: { _, _ in throw TestError.unused },
      list: { [] },
      load: load,
      loadPages: { _ in throw TestError.unused },
      pageURLs: { _ in throw TestError.unused },
      addPages: { _, _ in throw TestError.unused },
      deletePage: { _, _ in throw TestError.unused },
      reorderPages: { _, _ in throw TestError.unused },
      save: { _ in throw TestError.unused },
      delete: { _ in throw TestError.unused })
  }

  private enum TestError: Error {
    case loadFailed
    case unused
  }
}
