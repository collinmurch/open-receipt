import XCTest

@testable import open_receipt

@MainActor
final class ReceiptAdjustmentQuestionTests: XCTestCase {
  func testNewDraftAsksNothing() {
    let draft = makeDraft()

    XCTAssertTrue(draft.unconfirmedAdjustments.isEmpty)
  }

  func testAsksAboutMissingTaxAndTip() {
    let draft = makeDraft()

    draft.askAboutMissingAdjustments()

    XCTAssertEqual(draft.unconfirmedAdjustments, [.tax, .tip])
  }

  func testDoesNotAskAboutTaxThatWasFound() {
    let draft = makeDraft(tax: 0.40, total: 4.90)

    draft.askAboutMissingAdjustments()

    XCTAssertEqual(draft.unconfirmedAdjustments, [.tip])
  }

  func testNeverAsksAboutSavings() {
    let draft = makeDraft()

    draft.askAboutMissingAdjustments()

    XCTAssertFalse(draft.unconfirmedAdjustments.contains(.savings))
  }

  func testConfirmingRecordsAmount() {
    let draft = makeDraft()
    draft.askAboutMissingAdjustments()

    draft.confirm(.tip, amount: 0.90)

    XCTAssertEqual(draft.tip, 0.90)
  }

  func testConfirmingStopsAsking() {
    let draft = makeDraft()
    draft.askAboutMissingAdjustments()

    draft.confirm(.tax, amount: 0.40)

    XCTAssertEqual(draft.unconfirmedAdjustments, [.tip])
  }

  func testConfirmingRaisesTotalThatAddedUp() {
    let draft = makeDraft()
    draft.askAboutMissingAdjustments()

    draft.confirm(.tip, amount: 0.90)

    XCTAssertEqual(draft.total, 5.40)
  }

  func testConfirmingLeavesTotalThatDidNotAddUp() {
    let draft = makeDraft(total: 4.90)
    draft.askAboutMissingAdjustments()

    draft.confirm(.tax, amount: 0.40)

    XCTAssertEqual(draft.total, 4.90)
    XCTAssertTrue(draft.balance.isBalanced)
  }

  func testStoppingAskingStopsAsking() {
    let draft = makeDraft()
    draft.askAboutMissingAdjustments()

    draft.stopAsking(about: .tax)

    XCTAssertEqual(draft.unconfirmedAdjustments, [.tip])
  }

  func testStoppingAskingRecordsNothing() {
    let draft = makeDraft()
    draft.askAboutMissingAdjustments()

    draft.stopAsking(about: .tax)

    XCTAssertFalse(draft.adjustments.contains(.tax))
  }

  func testStoppingAskingLeavesTotal() {
    let draft = makeDraft()
    draft.askAboutMissingAdjustments()

    draft.stopAsking(about: .tip)

    XCTAssertEqual(draft.total, 4.50)
  }

  func testAnsweringMarksPersistedChange() {
    let draft = makeDraft()
    draft.askAboutMissingAdjustments()
    let revision = draft.persistenceRevision

    draft.stopAsking(about: .tip)

    XCTAssertGreaterThan(draft.persistenceRevision, revision)
  }

  func testImpliedTaxIsWhatTotalHasBeyondSubtotal() {
    let draft = makeDraft(total: 4.90)

    XCTAssertEqual(draft.impliedTax, 0.40)
  }

  func testNoImpliedTaxWhenTotalAddsUp() {
    let draft = makeDraft()

    XCTAssertNil(draft.impliedTax)
  }

  func testNoImpliedTaxWhenTotalIsLess() {
    let draft = makeDraft(total: 4)

    XCTAssertNil(draft.impliedTax)
  }

  func testNoImpliedTaxWhenSubtotalMissesAnItem() {
    let draft = makeDraft(subtotal: 6.50, total: 7)

    XCTAssertNil(draft.impliedTax)
  }

  func testNoImpliedTaxWithoutPrintedSubtotal() {
    let draft = makeDraft(subtotal: 0, total: 4.90)

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
    let draft = makeDraft(total: 0)

    draft.askAboutMissingAdjustments()

    XCTAssertEqual(draft.unconfirmedAdjustments, [.tax, .tip])
  }

  func testConfirmingLeavesTotalThatWasNotRead() {
    let draft = makeDraft(total: 0)
    draft.askAboutMissingAdjustments()

    draft.confirm(.tip, amount: 0.90)

    XCTAssertEqual(draft.total, 0)
  }

  func testUnconfirmedAdjustmentsSurviveRoundTrip() throws {
    let draft = makeDraft()
    draft.askAboutMissingAdjustments()
    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    let loaded = try ReceiptDraft(document: document)

    XCTAssertEqual(loaded.unconfirmedAdjustments, [.tax, .tip])
  }

  func testNothingToAskIsLeftOutOfDocument() {
    let draft = makeDraft()

    let document = ReceiptDocument.pending(id: draft.id).updating(from: draft)

    XCTAssertNil(document.presentation.unconfirmedAdjustments)
  }

  func testDocumentSavedBeforeQuestionsAsksNothing() throws {
    let draft = makeDraft()
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
    let center = makeCenter(receipt: makeReceipt())

    let document = try await recognize(with: center)

    XCTAssertEqual(document.presentation.unconfirmedAdjustments, [.tax, .tip])
  }

  func testRecognizedReceiptWithTaxAndTipAsksNothing() async throws {
    let center = makeCenter(receipt: makeReceipt(tax: 0.40, tip: 1, total: 5.90))

    let document = try await recognize(with: center)

    XCTAssertNil(document.presentation.unconfirmedAdjustments)
  }

  func testRescanDoesNotAskAboutEnteredTip() async throws {
    let scan = ReceiptScan(pages: [])
    let previous = makeDraft(id: scan.id)
    previous.tip = 1
    let stored = ReceiptDocument.pending(id: scan.id).updating(from: previous)
    let center = makeCenter(receipt: makeReceipt())

    let outcome = await center.recognize(scan, replacing: stored).outcome

    guard case .recognized(let document) = outcome else {
      return XCTFail("Expected a recognized receipt")
    }
    XCTAssertEqual(document.presentation.unconfirmedAdjustments, [.tax])
  }

  private func makeDraft(
    id: UUID = UUID(),
    subtotal: Double = 4.50,
    tax: Double = 0,
    total: Double = 4.50
  ) -> ReceiptDraft {
    ReceiptDraft(receipt: makeReceipt(subtotal: subtotal, tax: tax, total: total), id: id)
  }

  private func makeReceipt(
    subtotal: Double = 4.50,
    tax: Double = 0,
    tip: Double = 0,
    total: Double = 4.50
  ) -> ParsedReceipt {
    ParsedReceipt(
      merchantName: "Cafe",
      subtotal: subtotal,
      tax: tax,
      tip: tip,
      total: total,
      items: [ReceiptItem(description: "Coffee", quantity: 1, lineTotal: 4.50)])
  }

  private func makeCenter(receipt: ParsedReceipt) -> ReceiptRecognitionCenter {
    var storage = ReceiptStorageClient.unimplemented
    storage.create = { scan, style in ReceiptDocument.pending(id: scan.id, style: style) }
    storage.list = { [] }
    storage.loadPages = { _ in [] }
    storage.pageURLs = { _ in [] }
    storage.save = { _ in }
    storage.delete = { _ in }
    return ReceiptRecognitionCenter(
      parsingClient: ReceiptParsingClient(usesSampleData: false) { _ in receipt },
      storage: storage,
      access: .unlimited(),
      owner: { nil },
      connectivity: .immediate,
      connectionRetryDelay: .zero)
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
