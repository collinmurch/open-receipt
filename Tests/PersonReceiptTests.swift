import XCTest

@testable import open_receipt

@MainActor
final class PersonReceiptTests: XCTestCase {
  func testOwedIsPersonsShare() throws {
    let sam = Person.fixture(name: "Sam")
    let draft = makeDraft()
    let participant = draft.addPerson(sam)
    draft.items[0].participantIDs = [participant.id]
    draft.items[1].participantIDs = [draft.participants[0].id]

    let receipt = try XCTUnwrap(make(draft, person: sam, people: [sam]))

    XCTAssertEqual(receipt.owed ?? 0, 6.6, accuracy: 0.001)
    XCTAssertEqual(receipt.currency, "USD")
  }

  func testOwedIsNilWhileItemsAreUnassigned() throws {
    let sam = Person.fixture(name: "Sam")
    let draft = makeDraft()
    let participant = draft.addPerson(sam)
    draft.items[0].participantIDs = [participant.id]

    let receipt = try XCTUnwrap(make(draft, person: sam, people: [sam]))

    XCTAssertNil(receipt.owed)
  }

  func testPersonNotOnReceiptIsLeftOut() {
    let sam = Person.fixture(name: "Sam")
    let alex = Person.fixture(name: "Alex")
    let draft = makeDraft()
    draft.addPerson(alex)

    XCTAssertNil(make(draft, person: sam, people: [sam, alex]))
  }

  func testLegacyParticipantMatchesByName() throws {
    let sam = Person.fixture(name: "Sam")
    let draft = makeDraft()
    draft.addManualParticipant(named: "Sam")
    var document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    document.split?.participants[1].personID = nil

    XCTAssertNotNil(
      PersonReceipt.make(
        summary: makeSummary(id: draft.id),
        document: document,
        person: sam,
        people: [sam]))
  }

  func testCurrentUserIsNotMatched() {
    let owner = Person.fixture(name: "Alex", contactIdentifier: "me")
    let draft = makeDraft()
    draft.setOwner(ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

    XCTAssertNil(make(draft, person: owner, people: [owner]))
  }

  func testLoadSkipsUnreadAndUnavailableReceipts() async {
    let sam = Person.fixture(name: "Sam")
    let draft = makeDraft()
    draft.addPerson(sam)
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    let summaries = [
      makeSummary(id: UUID(), status: .pending, personIDs: [sam.id]),
      makeSummary(id: UUID(), isUnavailable: true, personIDs: [sam.id]),
      makeSummary(id: draft.id, personIDs: [sam.id]),
    ]

    let receipts = await PersonReceipt.load(
      for: sam,
      in: summaries,
      people: [sam],
      storage: makeStorage { _ in document })

    XCTAssertEqual(receipts.map(\.id), [draft.id])
  }

  func testLoadSkipsReceiptsThatFailToLoad() async {
    let sam = Person.fixture(name: "Sam")

    let receipts = await PersonReceipt.load(
      for: sam,
      in: [makeSummary(id: UUID(), personIDs: [sam.id])],
      people: [sam],
      storage: makeStorage { _ in throw TestError.failed })

    XCTAssertTrue(receipts.isEmpty)
  }

  func testLoadSkipsReceiptsWithoutThePersonUnloaded() async {
    let sam = Person.fixture(name: "Sam")
    let loads = CallCounter()

    let receipts = await PersonReceipt.load(
      for: sam,
      in: [makeSummary(id: UUID(), personIDs: [UUID()])],
      people: [sam],
      storage: makeStorage { _ in
        await loads.increment()
        throw TestError.failed
      })

    let count = await loads.value
    XCTAssertTrue(receipts.isEmpty)
    XCTAssertEqual(count, 0)
  }

  func testSummaryMayIncludeSavedPersonOnReceipt() throws {
    let sam = Person.fixture(name: "Sam")
    let draft = makeDraft()
    draft.addPerson(sam)
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    XCTAssertTrue(try ReceiptSummary(document).mayInclude(sam))
  }

  func testSummaryExcludesSavedPersonNotOnReceipt() throws {
    let draft = makeDraft()
    draft.addPerson(.fixture(name: "Alex"))
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    XCTAssertFalse(try ReceiptSummary(document).mayInclude(.fixture(name: "Sam")))
  }

  func testSummaryMayIncludeAnyoneWithUnlinkedParticipant() throws {
    let draft = makeDraft()
    draft.addManualParticipant(named: "Sam")
    var document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    document.split?.participants[1].personID = nil

    XCTAssertTrue(try ReceiptSummary(document).mayInclude(.fixture(name: "Sam")))
  }

  private func make(_ draft: ReceiptDraft, person: Person, people: [Person]) -> PersonReceipt? {
    PersonReceipt.make(
      summary: makeSummary(id: draft.id),
      document: ReceiptDocument.pending(id: draft.id).updating(from: draft),
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

  private func makeSummary(
    id: UUID,
    status: ReceiptDocument.Recognition.Status = .succeeded,
    isUnavailable: Bool = false,
    personIDs: Set<UUID> = []
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
      unavailableDescription: nil,
      personIDs: personIDs)
  }

  private func makeStorage(
    load: @escaping @Sendable (UUID) async throws -> ReceiptDocument
  ) -> ReceiptStorageClient {
    var storage = ReceiptStorageClient.unimplemented
    storage.list = { [] }
    storage.load = load
    return storage
  }
}
