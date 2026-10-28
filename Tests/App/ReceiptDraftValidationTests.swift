import XCTest

@testable import open_receipt

@MainActor
final class ReceiptDraftValidationTests: XCTestCase {
  func testEmptyItemNameProducesValidationIssue() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.items[0].description = "  "

    XCTAssertTrue(
      draft.issues.contains(.missingItemDescription(draft.items[0].id)))
  }

  func testNonPositiveQuantityProducesValidationIssue() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.items[0].quantity = 0

    XCTAssertTrue(draft.issues.contains(.invalidItemQuantity(draft.items[0].id)))
  }

  func testValidItemHasNoValidationIssues() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    XCTAssertTrue(draft.items[0].issues.isEmpty)
  }

  func testItemReportsEachInvalidField() {
    var item = ReceiptDraft.fixture(items: ["Coffee": 4.5]).items[0]
    item.description = ""
    item.quantity = -1

    XCTAssertEqual(
      item.issues, [.missingItemDescription(item.id), .invalidItemQuantity(item.id)])
  }

  func testInvalidCurrencyProducesValidationIssue() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.currency = "US"

    XCTAssertTrue(draft.issues.contains(.invalidCurrency))
  }

  func testItemIssuesAreShownBesideTheirItem() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.items[0].description = ""
    let id = draft.items[0].id

    XCTAssertEqual(draft.issues(at: .item(id)), [.missingItemDescription(id)])
  }

  func testItemIssuesStayOffOtherRows() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.items[0].description = ""

    XCTAssertTrue(draft.issues(at: .amount(.total)).isEmpty)
  }

  func testNegativeSubtotalIsShownBesideSubtotal() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.setSubtotal(-1)

    XCTAssertEqual(draft.issues(at: .amount(.subtotal)), [.negativeAmount(.subtotal)])
  }

  func testNegativeTaxIsShownBesideTax() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.tax = -1

    XCTAssertEqual(
      draft.issues(at: .amount(.adjustment(.tax))), [.negativeAmount(.adjustment(.tax))])
  }

  func testRemovedAdjustmentHasNoIssues() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.tip = -1
    draft.removeAdjustment(.tip)

    XCTAssertTrue(draft.issues(at: .amount(.adjustment(.tip))).isEmpty)
  }

  func testZeroTotalIsShownBesideTotal() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.total = 0

    XCTAssertEqual(draft.issues(at: .amount(.total)), [.zeroTotal])
  }

  func testInvalidCurrencyIsShownBesideCurrency() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.currency = "US"

    XCTAssertEqual(draft.issues(at: .currency), [.invalidCurrency])
  }
}
