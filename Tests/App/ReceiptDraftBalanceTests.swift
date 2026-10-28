import XCTest

@testable import open_receipt

@MainActor
final class ReceiptDraftBalanceTests: XCTestCase {
  func testTaxMovesTotalThatAddedUp() {
    let draft = ReceiptDraft.fixture()

    draft.tax = 2.50

    XCTAssertEqual(draft.total, 32.50)
  }

  func testBalanceFollowsItemEditedInPlace() {
    let draft = ReceiptDraft.fixture()
    XCTAssertTrue(draft.balance.isBalanced)

    draft.items[0].lineTotal = 12

    XCTAssertEqual(draft.balance.itemsTotal, 32)
    XCTAssertFalse(draft.balance.isBalanced)
  }

  func testTaxLeavesTotalThatDidNotAddUp() {
    let draft = ReceiptDraft.fixture(total: 32.50)

    draft.tax = 2.50

    XCTAssertEqual(draft.total, 32.50)
    XCTAssertTrue(draft.balance.isBalanced)
  }

  func testChangingTaxMovesTotalByTheChange() {
    let draft = ReceiptDraft.fixture(tax: 2.50)

    draft.tax = 3

    XCTAssertEqual(draft.total, 33)
  }

  func testAddingTipMovesTotal() {
    let draft = ReceiptDraft.fixture()

    draft.addAdjustment(.tip, amount: 6)

    XCTAssertEqual(draft.total, 36)
  }

  func testRemovingTipMovesTotal() {
    let draft = ReceiptDraft.fixture()
    draft.addAdjustment(.tip, amount: 6)

    draft.removeAdjustment(.tip)

    XCTAssertEqual(draft.total, 30)
  }

  func testSavingsLowerTotal() {
    let draft = ReceiptDraft.fixture()

    draft.savings = 5

    XCTAssertEqual(draft.total, 25)
  }

  func testSavingsAlreadyInPricesKeepTheirPlacement() {
    let draft = ReceiptDraft.fixture(tax: 3, savings: 2, total: 33)

    draft.tax = 4

    XCTAssertEqual(draft.total, 34)
    XCTAssertFalse(draft.balance.subtractsSavingsFromSubtotal)
  }

  func testSubtotalMovesTotalThatAddedUp() {
    let draft = ReceiptDraft.fixture(tax: 3)

    draft.setSubtotal(40)

    XCTAssertEqual(draft.total, 43)
  }

  func testCorrectingMisreadSubtotalLeavesTotal() {
    let draft = ReceiptDraft.fixture(subtotal: 80, tax: 3, total: 33)

    draft.setSubtotal(30)

    XCTAssertEqual(draft.total, 33)
    XCTAssertTrue(draft.balance.isBalanced)
  }

  func testAddedItemCarriesLineTotal() throws {
    let draft = ReceiptDraft.fixture()

    let id = draft.addItem(lineTotal: 5)

    XCTAssertEqual(try XCTUnwrap(draft.items.first { $0.id == id }).lineTotal, 5)
  }

  func testTypingTipKeepsTotalThatDidNotAddUpWhenTypingBegan() {
    let draft = ReceiptDraft.fixture(tax: 3, total: 33.50)
    draft.addAdjustment(.tip)
    draft.beginEditing(.adjustment(.tip))

    for amount: Money in [0.05, 0.50, 5] { draft.tip = amount }

    XCTAssertEqual(draft.total, 33.50)
  }

  func testTypingTaxKeepsTotalThatDidNotAddUpWhenTypingBegan() {
    let draft = ReceiptDraft.fixture(total: 30.50)
    draft.addAdjustment(.tax)
    draft.beginEditing(.adjustment(.tax))

    for amount: Money in [0.05, 0.50, 5] { draft.tax = amount }

    XCTAssertEqual(draft.total, 30.50)
  }

  func testTypingSavingsKeepsTotalThatDidNotAddUpWhenTypingBegan() {
    let draft = ReceiptDraft.fixture(total: 29.50)
    draft.addAdjustment(.savings)
    draft.beginEditing(.adjustment(.savings))

    for amount: Money in [0.05, 0.50, 5] { draft.savings = amount }

    XCTAssertEqual(draft.total, 29.50)
  }

  func testTypingSubtotalKeepsTotalThatDidNotAddUpWhenTypingBegan() {
    let draft = ReceiptDraft.fixture(subtotal: 35, tax: 3, total: 33.50)
    draft.beginEditing(.subtotal)

    for amount: Money in [3.05, 30.50, 305] { draft.setSubtotal(amount) }

    XCTAssertEqual(draft.total, 33.50)
  }

  func testTypingTipMovesTotalThatAddedUpWhenTypingBegan() {
    let draft = ReceiptDraft.fixture(tax: 3)
    draft.addAdjustment(.tip)
    draft.beginEditing(.adjustment(.tip))

    for amount: Money in [0.05, 0.50, 5] { draft.tip = amount }

    XCTAssertEqual(draft.total, 38)
  }

  func testTypingAgainJudgesTotalWhenTypingBeganAgain() {
    let draft = ReceiptDraft.fixture(tax: 3, total: 33.50)
    draft.addAdjustment(.tip)
    draft.beginEditing(.adjustment(.tip))
    draft.tip = 0.50
    draft.endEditing()

    draft.beginEditing(.adjustment(.tip))
    draft.tip = 5

    XCTAssertEqual(draft.total, 38)
  }

  func testTypingIntoOneFieldLeavesOthersJudgedAsTheyAre() {
    let draft = ReceiptDraft.fixture(tax: 3)
    draft.addAdjustment(.tip)
    draft.beginEditing(.adjustment(.tax))

    draft.tip = 5

    XCTAssertEqual(draft.total, 38)
  }

  func testChangingTotalEndsTyping() {
    let draft = ReceiptDraft.fixture()
    draft.addAdjustment(.tax)
    draft.beginEditing(.adjustment(.tax))

    draft.total = 99
    draft.tax = 2

    XCTAssertEqual(draft.total, 99)
  }

  func testAddingAnotherAdjustmentEndsTyping() {
    let draft = ReceiptDraft.fixture(total: 30.50)
    draft.addAdjustment(.tax)
    draft.beginEditing(.adjustment(.tax))

    draft.addAdjustment(.tip, amount: 0.50)
    draft.tax = 1

    XCTAssertEqual(draft.total, 31.50)
  }

  func testAssigningItemsEndsTyping() throws {
    let draft = ReceiptDraft.fixture(total: 30.50)
    draft.addAdjustment(.tax)
    draft.beginEditing(.adjustment(.tax))
    let ownerID = draft.ownerID

    draft.toggleAssignment(of: [ownerID], to: try XCTUnwrap(draft.items.first?.id))
    draft.tax = 0.50
    draft.tax = 1

    XCTAssertEqual(draft.total, 31)
  }

  func testFollowingTotalRoundsToCents() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    draft.tip = 0.8125

    XCTAssertEqual(draft.total, 5.31)
  }

  func testTotalWithinHalfACentNeedsNoCorrection() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.tip = 0.8125
    draft.total = 5.31

    XCTAssertTrue(draft.balance.isBalanced)
  }

}
