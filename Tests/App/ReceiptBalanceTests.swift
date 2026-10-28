import XCTest

@testable import open_receipt

final class ReceiptBalanceTests: XCTestCase {
  func testReceiptThatAddsUpIsBalanced() {
    let balance = ReceiptBalance(input(items: [10, 20], subtotal: 30, tax: 3, total: 33))

    XCTAssertTrue(balance.isBalanced)
    XCTAssertEqual(balance.subtotalDifference, 0)
    XCTAssertEqual(balance.totalDifference, 0)
  }

  func testItemsShortOfSubtotalAreTheSubtotalDifference() {
    let balance = ReceiptBalance(input(items: [10, 20], subtotal: 35, tax: 3, total: 38))

    XCTAssertEqual(balance.subtotalDifference, 5)
    XCTAssertEqual(balance.totalDifference, 0)
  }

  func testItemsOverSubtotalAreNegative() {
    let balance = ReceiptBalance(input(items: [10, 20], subtotal: 25, tax: 3, total: 28))

    XCTAssertEqual(balance.subtotalDifference, -5)
  }

  func testTotalIsCheckedAgainstPrintedSubtotal() {
    let balance = ReceiptBalance(input(items: [10, 20], subtotal: 35, tax: 3, total: 39.50))

    XCTAssertEqual(balance.calculatedTotal, 38)
    XCTAssertEqual(balance.totalDifference, 1.50)
  }

  func testMissingSubtotalChecksTotalAgainstItems() {
    let balance = ReceiptBalance(input(items: [10, 20], subtotal: 0, tax: 3, total: 34))

    XCTAssertNil(balance.printedSubtotal)
    XCTAssertNil(balance.calculatedSubtotal)
    XCTAssertEqual(balance.subtotalDifference, 0)
    XCTAssertEqual(balance.totalDifference, 1)
  }

  func testMissingSubtotalShowsItemsAsSubtotal() {
    let balance = ReceiptBalance(input(items: [10, 20], subtotal: 0, total: 30))

    XCTAssertEqual(balance.subtotal, 30)
  }

  func testDifferenceWithinHalfAUnitIsBalanced() {
    let balance = ReceiptBalance(input(items: [4.50], subtotal: 4.50, tip: 0.8125, total: 5.31))

    XCTAssertTrue(balance.isBalanced)
  }

  func testSavingsAfterSubtotalLowerTotal() {
    let balance = ReceiptBalance(
      input(items: [10, 20], subtotal: 30, tax: 3, savings: 2, total: 31))

    XCTAssertTrue(balance.isBalanced)
    XCTAssertEqual(balance.placement, .afterSubtotal)
    XCTAssertTrue(balance.subtractsSavingsFromSubtotal)
    XCTAssertTrue(balance.subtractsSavingsFromItems)
  }

  func testSavingsInItemPricesUnderGrossSubtotal() {
    let balance = ReceiptBalance(
      input(items: [10, 20], subtotal: 32, tax: 3, savings: 2, total: 33))

    XCTAssertTrue(balance.isBalanced)
    XCTAssertTrue(balance.placement.isInItems)
    XCTAssertFalse(balance.placement.isInSubtotal)
    XCTAssertTrue(balance.subtractsSavingsFromSubtotal)
    XCTAssertFalse(balance.subtractsSavingsFromItems)
  }

  func testSavingsAlreadyInItemsAndSubtotal() {
    let balance = ReceiptBalance(
      input(items: [10, 20], subtotal: 30, tax: 3, savings: 2, total: 33))

    XCTAssertTrue(balance.isBalanced)
    XCTAssertFalse(balance.subtractsSavingsFromSubtotal)
    XCTAssertFalse(balance.subtractsSavingsFromItems)
  }

  func testSavingsTakenOffBeforeSubtotal() {
    let balance = ReceiptBalance(
      input(items: [10, 20], subtotal: 28, tax: 3, savings: 2, total: 31))

    XCTAssertTrue(balance.isBalanced)
    XCTAssertFalse(balance.subtractsSavingsFromSubtotal)
    XCTAssertTrue(balance.subtractsSavingsFromItems)
  }

  func testSavingsInItemsWithoutSubtotal() {
    let balance = ReceiptBalance(
      input(items: [10, 20], subtotal: 0, tax: 3, savings: 2, total: 33))

    XCTAssertTrue(balance.isBalanced)
    XCTAssertFalse(balance.subtractsSavingsFromSubtotal)
  }

  func testUnexplainedSavingsAreReadAfterSubtotal() {
    let balance = ReceiptBalance(
      input(items: [10, 20], subtotal: 40, tax: 3, savings: 2, total: 50))

    XCTAssertEqual(balance.placement, .afterSubtotal)
  }

  func testPlacementCanBeGiven() {
    let balance = ReceiptBalance(
      input(items: [10, 20], subtotal: 30, tax: 3, savings: 2, total: 33),
      placement: .afterSubtotal)

    XCTAssertEqual(balance.totalDifference, 2)
  }

  func testDifferencesUseCurrencyUnits() {
    let balance = ReceiptBalance(
      input(items: [1000], subtotal: 1000, tax: 80, total: 1081, currency: "JPY"))

    XCTAssertEqual(balance.totalDifferenceUnits, 1)
  }

  private func input(
    items: [Money],
    subtotal: Money,
    tax: Money = 0,
    tip: Money = 0,
    savings: Money = 0,
    total: Money,
    currency: String = "USD"
  ) -> ReceiptSplitInput {
    ReceiptSplitInput(
      items: items.map {
        ReceiptDraftItem(item: ReceiptItem(description: "Item", quantity: 1, lineTotal: $0))
      },
      participants: [],
      subtotal: subtotal,
      adjustments: ReceiptTotalAdjustments(tax: tax, tip: tip, savings: savings),
      total: total,
      currency: currency,
      adjustmentMethod: .proportional)
  }
}
