import XCTest

@testable import open_receipt

@MainActor
final class ReceiptDraftBalanceTests: XCTestCase {
  func testTaxMovesTotalThatAddedUp() {
    let draft = makeDraft()

    draft.tax = 2.50

    XCTAssertEqual(draft.total, 32.50, accuracy: 0.000_1)
  }

  func testBalanceFollowsItemEditedInPlace() {
    let draft = makeDraft()
    XCTAssertTrue(draft.balance.isBalanced)

    draft.items[0].lineTotal = 12

    XCTAssertEqual(draft.balance.itemsTotal, 32, accuracy: 0.000_1)
    XCTAssertFalse(draft.balance.isBalanced)
  }

  func testTaxLeavesTotalThatDidNotAddUp() {
    let draft = makeDraft(total: 32.50)

    draft.tax = 2.50

    XCTAssertEqual(draft.total, 32.50, accuracy: 0.000_1)
    XCTAssertTrue(draft.balance.isBalanced)
  }

  func testChangingTaxMovesTotalByTheChange() {
    let draft = makeDraft(tax: 2.50, total: 32.50)

    draft.tax = 3

    XCTAssertEqual(draft.total, 33, accuracy: 0.000_1)
  }

  func testAddingTipMovesTotal() {
    let draft = makeDraft()

    draft.addAdjustment(.tip, amount: 6)

    XCTAssertEqual(draft.total, 36, accuracy: 0.000_1)
  }

  func testRemovingTipMovesTotal() {
    let draft = makeDraft()
    draft.addAdjustment(.tip, amount: 6)

    draft.removeAdjustment(.tip)

    XCTAssertEqual(draft.total, 30, accuracy: 0.000_1)
  }

  func testSavingsLowerTotal() {
    let draft = makeDraft()

    draft.savings = 5

    XCTAssertEqual(draft.total, 25, accuracy: 0.000_1)
  }

  func testSavingsAlreadyInPricesKeepTheirPlacement() {
    let draft = makeDraft(tax: 3, savings: 2, total: 33)

    draft.tax = 4

    XCTAssertEqual(draft.total, 34, accuracy: 0.000_1)
    XCTAssertFalse(draft.balance.subtractsSavingsFromSubtotal)
  }

  func testSubtotalMovesTotalThatAddedUp() {
    let draft = makeDraft(tax: 3, total: 33)

    draft.setSubtotal(40)

    XCTAssertEqual(draft.total, 43, accuracy: 0.000_1)
  }

  func testCorrectingMisreadSubtotalLeavesTotal() {
    let draft = makeDraft(subtotal: 80, tax: 3, total: 33)

    draft.setSubtotal(30)

    XCTAssertEqual(draft.total, 33, accuracy: 0.000_1)
    XCTAssertTrue(draft.balance.isBalanced)
  }

  func testMatchingSubtotalToItemsMovesTotal() {
    let draft = makeDraft(subtotal: 35, tax: 3, total: 38)

    draft.matchSubtotalToItems()

    XCTAssertEqual(draft.subtotal, 30, accuracy: 0.000_1)
    XCTAssertEqual(draft.total, 33, accuracy: 0.000_1)
  }

  func testMatchingSubtotalWithoutPrintedSubtotalDoesNothing() {
    let draft = makeDraft(subtotal: 0)

    draft.matchSubtotalToItems()

    XCTAssertEqual(draft.subtotal, 0)
  }

  func testAddedItemCarriesLineTotal() throws {
    let draft = makeDraft()

    let id = draft.addItem(lineTotal: 5)

    XCTAssertEqual(try XCTUnwrap(draft.items.first { $0.id == id }).lineTotal, 5)
  }

  func testTipBaseBeforeTaxIsSubtotal() {
    let draft = makeDraft(subtotal: 32, tax: 3, total: 35)

    XCTAssertEqual(draft.tipBaseAmount, 32, accuracy: 0.000_1)
  }

  func testTipBaseWithoutSubtotalIsItems() {
    let draft = makeDraft(subtotal: 0, tax: 3, total: 33)

    XCTAssertEqual(draft.tipBaseAmount, 30, accuracy: 0.000_1)
  }

  func testTipBelowTaxAddsTax() {
    let draft = makeDraft(tax: 3, total: 33, order: [.tax, .tip, .savings])

    XCTAssertEqual(draft.tipBaseAmount, 33, accuracy: 0.000_1)
  }

  func testTipAboveSavingsLeavesThemOut() {
    let draft = makeDraft(tax: 3, savings: 2, total: 31, order: [.tax, .tip, .savings])

    XCTAssertEqual(draft.tipBaseAmount, 33, accuracy: 0.000_1)
  }

  func testTipBelowSavingsTakesThemOff() {
    let draft = makeDraft(tax: 3, savings: 2, total: 31, order: [.tax, .savings, .tip])

    XCTAssertEqual(draft.tipBaseAmount, 31, accuracy: 0.000_1)
  }

  func testTipBelowSavingsOnlyTakesThemOffSubtotal() {
    let draft = makeDraft(savings: 2, total: 28, order: [.savings, .tip, .tax])

    XCTAssertEqual(draft.tipBaseAmount, 28, accuracy: 0.000_1)
  }

  func testTipBelowSavingsInSubtotalLeavesSubtotal() {
    let draft = makeDraft(tax: 3, savings: 2, total: 33, order: [.tax, .savings, .tip])

    XCTAssertEqual(draft.tipBaseAmount, 33, accuracy: 0.000_1)
  }

  func testTipBaseLeavesOutTip() {
    let draft = makeDraft(tax: 3, total: 33, order: [.tax, .tip, .savings])
    draft.tip = 6

    XCTAssertEqual(draft.tipBaseAmount, 33, accuracy: 0.000_1)
  }

  func testTipAboveTaxIsBeforeTax() {
    XCTAssertFalse(makeDraft(tax: 3, total: 33).isTipAfterTax)
  }

  func testTipBelowTaxIsAfterTax() {
    XCTAssertTrue(makeDraft(tax: 3, total: 33, order: [.tax, .tip, .savings]).isTipAfterTax)
  }

  func testTipWithoutSavingsDoesNotNameThem() {
    XCTAssertNil(makeDraft(tax: 3, total: 33).isTipAfterSavings)
  }

  func testTipAboveSavingsTakenOffAfterSubtotalIsBeforeThem() {
    let draft = makeDraft(tax: 3, savings: 2, total: 31)

    XCTAssertEqual(draft.isTipAfterSavings, false)
  }

  func testTipAboveSavingsInSubtotalIsAfterThem() {
    let draft = makeDraft(subtotal: 28, tax: 3, savings: 2, total: 31)

    XCTAssertEqual(draft.isTipAfterSavings, true)
  }

  func testTipBelowSavingsIsAfterThem() {
    let draft = makeDraft(tax: 3, savings: 2, total: 31, order: [.tax, .savings, .tip])

    XCTAssertEqual(draft.isTipAfterSavings, true)
  }

  func testMovingSuggestedTipBelowTaxKeepsItsPercentage() {
    let draft = makeDraft(tax: 3, total: 33)
    draft.addAdjustment(.tip, amount: 6)

    draft.setAdjustmentOrder([.tax, .tip, .savings], percentages: [18, 20, 22])

    XCTAssertEqual(draft.adjustmentOrder, [.tax, .tip, .savings])
    XCTAssertEqual(draft.tip, 6.60, accuracy: 0.000_1)
  }

  func testMovingSuggestedTipMovesTotal() {
    let draft = makeDraft(tax: 3, total: 33)
    draft.addAdjustment(.tip, amount: 6)

    draft.setAdjustmentOrder([.tax, .tip, .savings], percentages: [18, 20, 22])

    XCTAssertEqual(draft.total, 39.60, accuracy: 0.000_1)
  }

  func testMovingSuggestedTipAboveTaxKeepsItsPercentage() {
    let draft = makeDraft(tax: 3, total: 33, order: [.tax, .tip, .savings])
    draft.addAdjustment(.tip, amount: 6.60)

    draft.setAdjustmentOrder([.tip, .tax, .savings], percentages: [18, 20, 22])

    XCTAssertEqual(draft.tip, 6, accuracy: 0.000_1)
  }

  func testMovingSuggestedTipBelowSavingsKeepsItsPercentage() {
    let draft = makeDraft(savings: 5, total: 25)
    draft.addAdjustment(.tip, amount: 6)

    draft.setAdjustmentOrder([.tax, .savings, .tip], percentages: [18, 20, 22])

    XCTAssertEqual(draft.tip, 5, accuracy: 0.000_1)
  }

  func testMovingCustomTipKeepsItsAmount() {
    let draft = makeDraft(tax: 3, total: 33)
    draft.addAdjustment(.tip, amount: 5)

    draft.setAdjustmentOrder([.tax, .tip, .savings], percentages: [18, 20, 22])

    XCTAssertEqual(draft.tip, 5, accuracy: 0.000_1)
  }

  func testMovingWithoutTipAddsNone() {
    let draft = makeDraft(tax: 3, total: 33)

    draft.setAdjustmentOrder([.tax, .tip, .savings], percentages: [18, 20, 22])

    XCTAssertFalse(draft.adjustments.contains(.tip))
  }

  func testOrderMissingAnAdjustmentIsIgnored() {
    let draft = makeDraft()

    draft.setAdjustmentOrder([.tax, .tip])

    XCTAssertEqual(draft.adjustmentOrder, [.tip, .tax, .savings])
  }

  func testOrderBeforeTaxListsTipFirst() {
    XCTAssertEqual(ReceiptTotalAdjustment.order(tipBase: .beforeTax), [.tip, .tax, .savings])
  }

  func testOrderAfterTaxListsTaxFirst() {
    XCTAssertEqual(ReceiptTotalAdjustment.order(tipBase: .afterTax), [.tax, .tip, .savings])
  }

  private func makeDraft(
    subtotal: Double = 30,
    tax: Double = 0,
    savings: Double = 0,
    total: Double = 30,
    order: [ReceiptTotalAdjustment] = [.tip, .tax, .savings]
  ) -> ReceiptDraft {
    ReceiptDraft(
      receipt: ParsedReceipt(
        merchantName: "Cafe",
        subtotal: subtotal,
        tax: tax,
        savings: savings,
        total: total,
        items: [
          ReceiptItem(description: "Coffee", quantity: 1, lineTotal: 10),
          ReceiptItem(description: "Breakfast", quantity: 1, lineTotal: 20),
        ]),
      adjustmentOrder: order)
  }
}
