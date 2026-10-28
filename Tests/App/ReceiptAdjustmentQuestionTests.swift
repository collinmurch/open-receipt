import XCTest

@testable import open_receipt

@MainActor
final class ReceiptAdjustmentQuestionTests: XCTestCase {
  func testNewDraftAsksNothing() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    XCTAssertTrue(draft.unconfirmedAdjustments.isEmpty)
  }

  func testAsksAboutMissingTaxAndTip() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    draft.askAboutMissingAdjustments()

    XCTAssertEqual(draft.unconfirmedAdjustments, [.tax, .tip])
  }

  func testDoesNotAskAboutTaxThatWasFound() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5], tax: 0.40)

    draft.askAboutMissingAdjustments()

    XCTAssertEqual(draft.unconfirmedAdjustments, [.tip])
  }

  func testNeverAsksAboutSavings() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    draft.askAboutMissingAdjustments()

    XCTAssertFalse(draft.unconfirmedAdjustments.contains(.savings))
  }

  func testConfirmingRecordsAmount() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.askAboutMissingAdjustments()

    draft.confirm(.tip, amount: 0.90)

    XCTAssertEqual(draft.tip, 0.90)
  }

  func testConfirmingStopsAsking() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.askAboutMissingAdjustments()

    draft.confirm(.tax, amount: 0.40)

    XCTAssertEqual(draft.unconfirmedAdjustments, [.tip])
  }

  func testConfirmingRaisesTotalThatAddedUp() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.askAboutMissingAdjustments()

    draft.confirm(.tip, amount: 0.90)

    XCTAssertEqual(draft.total, 5.40)
  }

  func testConfirmingLeavesTotalThatDidNotAddUp() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5], total: 4.90)
    draft.askAboutMissingAdjustments()

    draft.confirm(.tax, amount: 0.40)

    XCTAssertEqual(draft.total, 4.90)
    XCTAssertTrue(draft.balance.isBalanced)
  }

  func testStoppingAskingStopsAsking() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.askAboutMissingAdjustments()

    draft.stopAsking(about: .tax)

    XCTAssertEqual(draft.unconfirmedAdjustments, [.tip])
  }

  func testStoppingAskingRecordsNothing() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.askAboutMissingAdjustments()

    draft.stopAsking(about: .tax)

    XCTAssertFalse(draft.adjustments.contains(.tax))
  }

  func testStoppingAskingLeavesTotal() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.askAboutMissingAdjustments()

    draft.stopAsking(about: .tip)

    XCTAssertEqual(draft.total, 4.50)
  }

  func testAnsweringMarksPersistedChange() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.askAboutMissingAdjustments()
    let revision = draft.persistenceRevision

    draft.stopAsking(about: .tip)

    XCTAssertGreaterThan(draft.persistenceRevision, revision)
  }

  func testImpliedTaxIsWhatTotalHasBeyondSubtotal() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5], total: 4.90)

    XCTAssertEqual(draft.impliedTax, 0.40)
  }

  func testNoImpliedTaxWhenTotalAddsUp() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    XCTAssertNil(draft.impliedTax)
  }

  func testNoImpliedTaxWhenTotalIsLess() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5], total: 4)

    XCTAssertNil(draft.impliedTax)
  }

  func testNoImpliedTaxWhenSubtotalMissesAnItem() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5], subtotal: 6.50, total: 7)

    XCTAssertNil(draft.impliedTax)
  }

  func testNoImpliedTaxWithoutPrintedSubtotal() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5], subtotal: 0, total: 4.90)

    XCTAssertNil(draft.impliedTax)
  }

  func testNoImpliedTaxWithoutItems() {
    let draft = ReceiptDraft(receipt: ParsedReceipt(subtotal: 4.50, total: 4.90))

    XCTAssertNil(draft.impliedTax)
  }

  func testAsksNothingWithoutItems() {
    let draft = ReceiptDraft(receipt: ParsedReceipt(total: 4.90))

    draft.askAboutMissingAdjustments()

    XCTAssertTrue(draft.unconfirmedAdjustments.isEmpty)
  }

  func testAsksNothingWhenItemsHaveNoPrices() {
    let draft = ReceiptDraft(
      receipt: ParsedReceipt(
        total: 4.90, items: [ReceiptItem(description: "Coffee", quantity: 1, lineTotal: 0)]))

    draft.askAboutMissingAdjustments()

    XCTAssertTrue(draft.unconfirmedAdjustments.isEmpty)
  }

  func testAsksWhenTotalWasNotRead() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5], total: 0)

    draft.askAboutMissingAdjustments()

    XCTAssertEqual(draft.unconfirmedAdjustments, [.tax, .tip])
  }

  func testConfirmingLeavesTotalThatWasNotRead() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5], total: 0)
    draft.askAboutMissingAdjustments()

    draft.confirm(.tip, amount: 0.90)

    XCTAssertEqual(draft.total, 0)
  }

  func testUnconfirmedAdjustmentsSurviveRoundTrip() throws {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.askAboutMissingAdjustments()
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loaded = try ReceiptDraft(document: document)

    XCTAssertEqual(loaded.unconfirmedAdjustments, [.tax, .tip])
  }

  func testNothingToAskIsLeftOutOfDocument() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    XCTAssertNil(document.presentation.unconfirmedAdjustments)
  }

  func testDocumentSavedBeforeQuestionsAsksNothing() throws {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.askAboutMissingAdjustments()
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoder.encode(document)) as? [String: Any])
    var presentation = try XCTUnwrap(json["presentation"] as? [String: Any])
    presentation.removeValue(forKey: "unconfirmedAdjustments")
    json["presentation"] = presentation
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let legacy = try decoder.decode(
      ReceiptDocument.self, from: JSONSerialization.data(withJSONObject: json))

    XCTAssertTrue(try ReceiptDraft(document: legacy).unconfirmedAdjustments.isEmpty)
  }

  func testRecognizedReceiptAsksAboutMissingTaxAndTip() async throws {
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: .reading(.fixture(items: ["Coffee": 4.5])))

    let document = try await recognize(with: center)

    XCTAssertEqual(document.presentation.unconfirmedAdjustments, [.tax, .tip])
  }

  func testRecognizedReceiptWithTaxAndTipAsksNothing() async throws {
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: .reading(.fixture(items: ["Coffee": 4.5], tax: 0.40, tip: 1)))

    let document = try await recognize(with: center)

    XCTAssertNil(document.presentation.unconfirmedAdjustments)
  }

  func testRescanDoesNotAskAboutEnteredTip() async throws {
    let scan = ReceiptScan(pages: [])
    let previous = ReceiptDraft.fixture(items: ["Coffee": 4.5], id: scan.id)
    previous.tip = 1
    let stored = ReceiptDocument.pending(id: scan.id).updating(from: previous)
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: .reading(.fixture(items: ["Coffee": 4.5])))

    let outcome = await center.recognize(scan, replacing: stored).outcome

    guard case .recognized(let document) = outcome else {
      return XCTFail("Expected a recognized receipt")
    }
    XCTAssertEqual(document.presentation.unconfirmedAdjustments, [.tax])
  }

  private func recognize(with center: ReceiptRecognitionCenter) async throws -> ReceiptDocument {
    let outcome = await center.recognize(ReceiptScan(pages: [])).outcome
    guard case .recognized(let document) = outcome else {
      XCTFail("Expected a recognized receipt")
      throw CancellationError()
    }
    return document
  }
}
