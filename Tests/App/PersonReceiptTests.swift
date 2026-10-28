import XCTest

@testable import open_receipt

@MainActor
final class PersonReceiptTests: XCTestCase {
  func testOwedIsPersonsShare() throws {
    let sam = Person.fixture(name: "Sam")
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    let participant = draft.addPerson(sam)
    draft.items[0].participantIDs = [participant.id]
    draft.items[1].participantIDs = [draft.ownerID]

    let receipt = try XCTUnwrap(make(draft, person: sam, people: [sam]))

    XCTAssertEqual(receipt.owed ?? 0, 6.6)
    XCTAssertEqual(receipt.currency, "USD")
  }

  func testOwedIsNilWhileItemsAreUnassigned() throws {
    let sam = Person.fixture(name: "Sam")
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    let participant = draft.addPerson(sam)
    draft.items[0].participantIDs = [participant.id]

    let receipt = try XCTUnwrap(make(draft, person: sam, people: [sam]))

    XCTAssertNil(receipt.owed)
  }

  func testPersonNotOnReceiptIsLeftOut() {
    let sam = Person.fixture(name: "Sam")
    let alex = Person.fixture(name: "Alex")
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    draft.addPerson(alex)

    XCTAssertNil(make(draft, person: sam, people: [sam, alex]))
  }

  func testLegacyParticipantMatchesByName() {
    let sam = Person.fixture(name: "Sam")
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    draft.addManualParticipant(named: "Sam")
    var document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    document.split?.participants[1].personID = nil

    XCTAssertNotNil(
      PersonReceipt.make(
        summary: .fixture(id: draft.id),
        document: document,
        person: sam,
        people: [sam]))
  }

  func testDeletedContactMatchesReaddedPerson() throws {
    let deleted = Person.fixture(name: "Sam", contactIdentifier: "contact-1")
    let readded = Person.fixture(name: "Sam", contactIdentifier: "contact-1")
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    let participant = draft.addPerson(deleted)
    draft.items[0].participantIDs = [participant.id]
    draft.items[1].participantIDs = [draft.ownerID]

    let receipt = try XCTUnwrap(make(draft, person: readded, people: [readded]))

    XCTAssertEqual(receipt.owed ?? 0, 6.6)
  }

  func testOwedAddsLegacyAndLinkedParticipantsForSamePerson() throws {
    let sam = Person.fixture(name: "Sam")
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    let legacy = draft.addManualParticipant(named: "Sam")
    let linked = draft.addPerson(sam)
    draft.items[0].participantIDs = [legacy.id]
    draft.items[1].participantIDs = [linked.id]
    var document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    document.split?.participants[1].personID = nil

    let receipt = try XCTUnwrap(
      PersonReceipt.make(
        summary: .fixture(id: draft.id),
        document: document,
        person: sam,
        people: [sam]))

    XCTAssertEqual(receipt.owed ?? 0, 11)
  }

  func testCurrentUserIsNotMatched() {
    let owner = Person.fixture(name: "Alex", contactIdentifier: "me")
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    draft.setOwner(ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

    XCTAssertNil(make(draft, person: owner, people: [owner]))
  }

  func testLoadSkipsUnreadAndUnavailableReceipts() async {
    let sam = Person.fixture(name: "Sam")
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    draft.addPerson(sam)
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    let summaries = [
      ReceiptSummary.fixture(status: .pending, personIDs: [sam.id]),
      ReceiptSummary.fixture(isUnavailable: true, personIDs: [sam.id]),
      ReceiptSummary.fixture(id: draft.id, personIDs: [sam.id]),
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
      in: [ReceiptSummary.fixture(personIDs: [sam.id])],
      people: [sam],
      storage: makeStorage { _ in throw TestError.failed })

    XCTAssertTrue(receipts.isEmpty)
  }

  func testLoadSkipsReceiptsWithoutThePersonUnloaded() async {
    let sam = Person.fixture(name: "Sam")
    let loads = CallCounter()

    let receipts = await PersonReceipt.load(
      for: sam,
      in: [ReceiptSummary.fixture(personIDs: [UUID()])],
      people: [sam],
      storage: makeStorage { _ in
        loads.increment()
        throw TestError.failed
      })

    let count = loads.value
    XCTAssertTrue(receipts.isEmpty)
    XCTAssertEqual(count, 0)
  }

  func testSummaryMayIncludeSavedPersonOnReceipt() throws {
    let sam = Person.fixture(name: "Sam")
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    draft.addPerson(sam)
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    XCTAssertTrue(try ReceiptSummary(document).mayInclude(sam))
  }

  func testSummaryExcludesSavedPersonNotOnReceipt() throws {
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    draft.addPerson(.fixture(name: "Alex"))
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    XCTAssertFalse(try ReceiptSummary(document).mayInclude(.fixture(name: "Sam")))
  }

  func testSummaryMayIncludeReaddedPersonForSameContact() throws {
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    draft.addPerson(.fixture(name: "Sam", contactIdentifier: "contact-1"))
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    XCTAssertTrue(
      try ReceiptSummary(document).mayInclude(
        .fixture(name: "Sam", contactIdentifier: "contact-1")))
  }

  func testSummaryExcludesOwnerContact() throws {
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    draft.setOwner(ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    XCTAssertFalse(
      try ReceiptSummary(document).mayInclude(.fixture(name: "Alex", contactIdentifier: "me")))
  }

  func testSummaryMayIncludeAnyoneWithUnlinkedParticipant() throws {
    let draft = ReceiptDraft.fixture(items: ["Sandwich": 6, "Coffee": 4], tax: 1)
    draft.addManualParticipant(named: "Sam")
    var document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    document.split?.participants[1].personID = nil

    XCTAssertTrue(try ReceiptSummary(document).mayInclude(.fixture(name: "Sam")))
  }

  private func make(_ draft: ReceiptDraft, person: Person, people: [Person]) -> PersonReceipt? {
    PersonReceipt.make(
      summary: .fixture(id: draft.id),
      document: ReceiptDocument.pending(id: draft.id).updating(from: draft),
      person: person,
      people: people)
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
