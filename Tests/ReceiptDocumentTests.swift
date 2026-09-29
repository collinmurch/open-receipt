import XCTest

@testable import open_receipt

@MainActor
final class ReceiptDocumentTests: XCTestCase {
  func testDraftRoundTripPreservesReceiptValues() throws {
    let draft = makeDraft()
    let document = pendingDocument(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.merchantName, "Cafe")
    XCTAssertEqual(loadedDraft.total, 11)
    XCTAssertEqual(loadedDraft.items.first?.description, "Coffee")
  }

  func testDraftRoundTripPreservesParticipantsAndAssignments() throws {
    let draft = makeDraft()
    let participant = draft.addManualParticipant(named: "Sam")
    draft.items[0].participantIDs.insert(participant.id)
    let document = pendingDocument(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.participants.map(\.displayName), ["Me", "Sam"])
    XCTAssertEqual(loadedDraft.items[0].participantIDs, [participant.id])
  }

  func testDraftRoundTripPreservesOwner() throws {
    let draft = makeDraft()
    draft.setOwner(ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))
    let document = pendingDocument(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.currentUser?.source, .currentUser(contactIdentifier: "me"))
    XCTAssertEqual(loadedDraft.currentUser?.displayName, "Alex")
  }

  func testDraftRoundTripPreservesGlobalPersonIdentifier() throws {
    let draft = makeDraft()
    let person = Person(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1),
      lastIncludedAt: Date(timeIntervalSince1970: 1),
      displayName: "Sam",
      contactIdentifier: nil,
      paymentMethods: .init())
    let participant = draft.addPerson(person)
    let document = pendingDocument(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.participant(forPersonID: person.id)?.id, participant.id)
  }

  func testDraftRoundTripPreservesAdjustmentMethod() throws {
    let draft = makeDraft()
    draft.adjustmentSplitMethod = .even
    let document = pendingDocument(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.adjustmentSplitMethod, .even)
  }

  func testDraftRoundTripPreservesCompletion() throws {
    let draft = makeDraft()
    draft.complete()
    let document = pendingDocument(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertTrue(loadedDraft.isCompleted)
  }

  func testDraftRoundTripPreservesLastRequestedDate() throws {
    let draft = makeDraft()
    let participant = draft.addManualParticipant(named: "Sam")
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    draft.recordRequest(for: participant.id, at: date)

    let document = pendingDocument(id: draft.id).updating(from: draft)
    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(
      loadedDraft.participants.first { $0.id == participant.id }?.lastRequestedAt,
      date)
  }

  func testParticipantWithoutLastRequestedDateDecodesWithNoDate() throws {
    let draft = makeDraft()
    draft.addManualParticipant(named: "Sam")
    let document = pendingDocument(id: draft.id).updating(from: draft)
    let data = try encoder.encode(document)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var split = try XCTUnwrap(json["split"] as? [String: Any])
    var participants = try XCTUnwrap(split["participants"] as? [[String: Any]])
    participants[1].removeValue(forKey: "lastRequestedAt")
    split["participants"] = participants
    json["split"] = split

    let legacyData = try JSONSerialization.data(withJSONObject: json)
    let decoded = try decoder.decode(ReceiptDocument.self, from: legacyData)

    XCTAssertNil(decoded.split?.participants[1].lastRequestedAt)
  }

  func testSavingsIsStoredAsSignedAdjustment() throws {
    let draft = makeDraft()
    draft.savings = 2

    let document = pendingDocument(id: draft.id).updating(from: draft)
    let savings = try XCTUnwrap(
      document.receipt?.amounts.adjustments.first { $0.kind == .savings })

    XCTAssertEqual(savings.amount.value, "-2.0")
  }

  func testAvatarDataIsNotStored() throws {
    let draft = makeDraft()
    let person = Person(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1),
      lastIncludedAt: Date(timeIntervalSince1970: 1),
      displayName: "Sam",
      contactIdentifier: "contact-1",
      paymentMethods: .init())
    draft.addPerson(person, avatarData: Data([1, 2, 3]))

    let document = pendingDocument(id: draft.id).updating(from: draft)
    let data = try encoder.encode(document)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))

    XCTAssertFalse(json.contains("avatar"))
  }

  func testDecimalStringEncodesAsJSONString() throws {
    let data = try JSONEncoder().encode(DecimalString(7.23))

    XCTAssertEqual(String(data: data, encoding: .utf8), "\"7.23\"")
  }

  func testDecimalStringRejectsNonFiniteValue() {
    let data = Data("\"nan\"".utf8)

    XCTAssertThrowsError(try JSONDecoder().decode(DecimalString.self, from: data))
  }

  func testDecimalStringRejectsNonFiniteEncoding() {
    XCTAssertThrowsError(try JSONEncoder().encode(DecimalString(.infinity)))
  }

  func testNeedsRescanWhenPagesWereNotRecognized() {
    var document = pendingDocument(id: UUID())
    document.scan.pages = [makePage()]

    XCTAssertTrue(document.needsRescan)
  }

  func testNeedsRescanAfterPageIsAdded() {
    var document = pendingDocument(id: UUID())
    let recognized = makePage()
    document.scan.pages = [recognized, makePage()]
    document.recognition.pageIDs = [recognized.id]

    XCTAssertTrue(document.needsRescan)
  }

  func testDoesNotNeedRescanWhenPagesWereRecognized() {
    var document = pendingDocument(id: UUID())
    let page = makePage()
    document.scan.pages = [page]
    document.recognition.pageIDs = [page.id]

    XCTAssertFalse(document.needsRescan)
  }

  func testReorderedPagesDoNotNeedRescan() {
    var document = pendingDocument(id: UUID())
    let pages = [makePage(), makePage()]
    document.scan.pages = pages.reversed()
    document.recognition.pageIDs = pages.map(\.id)

    XCTAssertFalse(document.needsRescan)
  }

  func testReceiptWithoutPagesDoesNotNeedRescan() {
    XCTAssertFalse(pendingDocument(id: UUID()).needsRescan)
  }

  func testRecognizedPagesEncodeAsPageIds() throws {
    var document = pendingDocument(id: UUID())
    document.recognition.pageIDs = [UUID()]

    let object = try JSONSerialization.jsonObject(with: encoder.encode(document.recognition))

    XCTAssertNotNil((object as? [String: Any])?["pageIds"])
  }

  private func makePage() -> ReceiptDocument.Page {
    ReceiptDocument.Page(id: UUID(), file: "pages/page.heic", mediaType: "image/heic")
  }

  private func makeDraft() -> ReceiptDraft {
    ReceiptDraft(
      receipt: ParsedReceipt(
        merchantName: "Cafe",
        date: "2026-08-11",
        subtotal: 10,
        tax: 1,
        savings: 1,
        total: 11,
        currency: "USD",
        payment: ReceiptPayment(method: "Card", last4: "4242"),
        items: [ReceiptItem(description: "Coffee", quantity: 2, lineTotal: 10)]),
      backgroundStyle: .mint)
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
      recognition: .init(
        status: .pending,
        contractVersion: 1,
        lastAttemptedAt: nil,
        completedAt: nil,
        failureMessage: nil),
      receipt: nil,
      split: nil)
  }

  private var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
