import XCTest

@testable import open_receipt

@MainActor
final class ReceiptDocumentTests: XCTestCase {
  func testDraftRoundTripPreservesReceiptValues() throws {
    let draft = makeDraft()
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.merchantName, "Cafe")
    XCTAssertEqual(loadedDraft.total, 11)
    XCTAssertEqual(loadedDraft.items.first?.description, "Coffee")
  }

  func testDraftRoundTripPreservesParticipantsAndAssignments() throws {
    let draft = makeDraft()
    let participant = draft.addManualParticipant(named: "Sam")
    draft.items[0].participantIDs.insert(participant.id)
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.participants.map(\.displayName), ["Me", "Sam"])
    XCTAssertEqual(loadedDraft.items[0].participantIDs, [participant.id])
  }

  func testDraftRoundTripPreservesOwner() throws {
    let draft = makeDraft()
    draft.setOwner(ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.currentUser?.source, .currentUser(contactIdentifier: "me"))
    XCTAssertEqual(loadedDraft.currentUser?.displayName, "Alex")
  }

  func testDraftRoundTripPreservesGlobalPersonIdentifier() throws {
    let draft = makeDraft()
    let person = Person.fixture(name: "Sam")
    let participant = draft.addPerson(person)
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.participant(forPersonID: person.id)?.id, participant.id)
  }

  func testDraftRoundTripPreservesAdjustmentMethod() throws {
    let draft = makeDraft()
    draft.adjustmentSplitMethod = .even
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.adjustmentSplitMethod, .even)
  }

  func testDraftRoundTripPreservesAdjustmentOrder() throws {
    let draft = makeDraft()
    draft.setAdjustmentOrder([.savings, .tax, .tip])
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.adjustmentOrder, [.savings, .tax, .tip])
  }

  func testSplitWithoutAdjustmentOrderDecodesWithNone() throws {
    let draft = makeDraft()
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    let data = try encoder.encode(document)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var split = try XCTUnwrap(json["split"] as? [String: Any])
    split.removeValue(forKey: "adjustmentOrder")
    json["split"] = split

    let legacyData = try JSONSerialization.data(withJSONObject: json)
    let decoded = try decoder.decode(ReceiptDocument.self, from: legacyData)

    XCTAssertNil(decoded.split?.adjustmentOrder)
  }

  func testDraftRoundTripPreservesCompletion() throws {
    let draft = makeDraft()
    draft.complete()
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertTrue(loadedDraft.isCompleted)
  }

  func testDraftRoundTripPreservesLastRequestedDate() throws {
    let draft = makeDraft()
    let participant = draft.addManualParticipant(named: "Sam")
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    draft.recordRequest(for: participant.id, at: date)

    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(
      loadedDraft.participants.first { $0.id == participant.id }?.lastRequestedAt,
      date)
  }

  func testParticipantWithoutLastRequestedDateDecodesWithNoDate() throws {
    let draft = makeDraft()
    draft.addManualParticipant(named: "Sam")
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
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

    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    let savings = try XCTUnwrap(
      document.receipt?.amounts.adjustments.first { $0.kind == .savings })

    XCTAssertEqual(savings.amount.value, "-2.0")
  }

  func testDraftRoundTripPreservesSavings() throws {
    let draft = makeDraft()
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.savings, 1)
  }

  func testDraftRoundTripPreservesNegativeSavings() throws {
    let draft = makeDraft()
    draft.savings = -2
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.savings, -2)
  }

  func testDraftRoundTripPreservesTipPercentage() throws {
    let draft = makeDraft()
    draft.setTipPercentage(20)
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertEqual(loadedDraft.tipPercentage, 20)
    XCTAssertEqual(loadedDraft.tip, draft.tip)
  }

  func testDraftRoundTripKeepsEnteredTipAnAmount() throws {
    let draft = makeDraft()
    draft.tip = 2
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loadedDraft = try ReceiptDraft(document: document)

    XCTAssertNil(loadedDraft.tipPercentage)
  }

  func testSplitWithoutTipPercentageDecodesWithNone() throws {
    let draft = makeDraft()
    draft.setTipPercentage(20)
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    let data = try encoder.encode(document)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var split = try XCTUnwrap(json["split"] as? [String: Any])
    split.removeValue(forKey: "tipPercentage")
    json["split"] = split

    let legacyData = try JSONSerialization.data(withJSONObject: json)
    let decoded = try decoder.decode(ReceiptDocument.self, from: legacyData)

    XCTAssertNil(decoded.split?.tipPercentage)
  }

  func testLegacyTipMatchingOneSuggestionFollowsIt() throws {
    let loaded = try ReceiptDraft(document: legacyDocument(itemTotal: 10, tip: 2))

    XCTAssertEqual(loaded.tipPercentage, 20)
  }

  func testLegacyTipMatchingSeveralSuggestionsStaysAnAmount() throws {
    let loaded = try ReceiptDraft(document: legacyDocument(itemTotal: 0.05, tip: 0.01))

    XCTAssertNil(loaded.tipPercentage)
  }

  func testLegacyTipMatchingNoSuggestionStaysAnAmount() throws {
    let loaded = try ReceiptDraft(document: legacyDocument(itemTotal: 10, tip: 2.50))

    XCTAssertNil(loaded.tipPercentage)
  }

  func testEnteredTipMatchingSuggestionStaysAnAmount() throws {
    let draft = tippedDraft(itemTotal: 10, tip: 2)
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loaded = try ReceiptDraft(document: document)

    XCTAssertNil(loaded.tipPercentage)
  }

  /// A receipt saved before tips followed a percentage.
  private func legacyDocument(itemTotal: Double, tip: Double) -> ReceiptDocument {
    let draft = tippedDraft(itemTotal: itemTotal, tip: tip)
    var document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    document.split?.tipPercentage = nil
    return document
  }

  private func tippedDraft(itemTotal: Double, tip: Double) -> ReceiptDraft {
    ReceiptDraft(
      receipt: ParsedReceipt(
        merchantName: "Cafe",
        subtotal: itemTotal,
        tip: tip,
        total: itemTotal + tip,
        items: [ReceiptItem(description: "Coffee", quantity: 1, lineTotal: itemTotal)]))
  }

  func testDecimalStringEncodesAsJSONString() throws {
    let data = try JSONEncoder().encode(DecimalString(7.23))

    XCTAssertEqual(String(data: data, encoding: .utf8), "\"7.23\"")
  }

  func testDecimalStringWritesSmallValueWithoutExponent() {
    XCTAssertEqual(DecimalString(0.00001).value, "0.00001")
  }

  func testDecimalStringWritesLargeValueWithoutExponent() {
    XCTAssertEqual(DecimalString(1e16).value, "10000000000000000")
  }

  func testDecimalStringWritesNegativeSmallValueWithoutExponent() {
    XCTAssertEqual(DecimalString(-3.25e-5).value, "-0.0000325")
  }

  func testDecimalStringWritesLargeFractionalValueWithoutExponent() {
    XCTAssertEqual(DecimalString(1.5e17).value, "150000000000000000")
  }

  func testDecimalStringKeepsWholeValueDecimalPoint() {
    XCTAssertEqual(DecimalString(-2).value, "-2.0")
  }

  func testDecimalStringRoundTripsSplitQuantity() {
    let quantity = 0.0001 / 7

    XCTAssertEqual(DecimalString(quantity).doubleValue, quantity)
  }

  func testDecimalStringRoundTripsSum() {
    let amount = 0.1 + 0.2

    XCTAssertEqual(DecimalString(amount).doubleValue, amount)
  }

  func testDecimalStringRoundTripsSmallestValue() {
    XCTAssertEqual(DecimalString(.leastNonzeroMagnitude).doubleValue, .leastNonzeroMagnitude)
  }

  func testDecimalStringRoundTripsLargestValue() {
    XCTAssertEqual(DecimalString(.greatestFiniteMagnitude).doubleValue, .greatestFiniteMagnitude)
  }

  func testDecimalStringMatchesSchemaPatternForSplitQuantity() {
    XCTAssertTrue(matchesSchemaDecimalPattern(DecimalString(0.0001 / 7).value))
  }

  func testDecimalStringMatchesSchemaPatternForLargeValue() {
    XCTAssertTrue(matchesSchemaDecimalPattern(DecimalString(1e16).value))
  }

  func testDecimalStringMatchesSchemaPatternForSmallestValue() {
    XCTAssertTrue(matchesSchemaDecimalPattern(DecimalString(-.leastNonzeroMagnitude).value))
  }

  func testDecimalStringReadsExponentForm() throws {
    let data = Data("\"1e-05\"".utf8)

    let decimal = try JSONDecoder().decode(DecimalString.self, from: data)

    XCTAssertEqual(decimal.doubleValue, 0.00001)
  }

  func testDecimalStringRejectsNonFiniteValue() {
    let data = Data("\"nan\"".utf8)

    XCTAssertThrowsError(try JSONDecoder().decode(DecimalString.self, from: data))
  }

  func testDecimalStringRejectsNonFiniteEncoding() {
    XCTAssertThrowsError(try JSONEncoder().encode(DecimalString(.infinity)))
  }

  func testNeedsRescanWhenPagesWereNotRecognized() {
    var document = ReceiptDocument.pending(id: UUID())
    document.scan.pages = [makePage()]

    XCTAssertTrue(document.needsRescan)
  }

  func testNeedsRescanAfterPageIsAdded() {
    var document = ReceiptDocument.pending(id: UUID())
    let recognized = makePage()
    document.scan.pages = [recognized, makePage()]
    document.recognition.pageIDs = [recognized.id]

    XCTAssertTrue(document.needsRescan)
  }

  func testDoesNotNeedRescanWhenPagesWereRecognized() {
    var document = ReceiptDocument.pending(id: UUID())
    let page = makePage()
    document.scan.pages = [page]
    document.recognition.pageIDs = [page.id]

    XCTAssertFalse(document.needsRescan)
  }

  func testReorderedPagesDoNotNeedRescan() {
    var document = ReceiptDocument.pending(id: UUID())
    let pages = [makePage(), makePage()]
    document.scan.pages = pages.reversed()
    document.recognition.pageIDs = pages.map(\.id)

    XCTAssertFalse(document.needsRescan)
  }

  func testReceiptWithoutPagesDoesNotNeedRescan() {
    XCTAssertFalse(ReceiptDocument.pending(id: UUID()).needsRescan)
  }

  func testRecognizedPagesEncodeAsPageIds() throws {
    var document = ReceiptDocument.pending(id: UUID())
    document.recognition.pageIDs = [UUID()]

    let object = try JSONSerialization.jsonObject(with: encoder.encode(document.recognition))

    XCTAssertNotNil((object as? [String: Any])?["pageIds"])
  }

  private func matchesSchemaDecimalPattern(_ value: String) -> Bool {
    value.wholeMatch(of: #/-?(0|[1-9][0-9]*)(\.[0-9]+)?/#) != nil
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
