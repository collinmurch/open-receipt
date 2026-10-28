import XCTest

@testable import open_receipt

@MainActor
final class ReceiptDraftTipTests: XCTestCase {
  func testChoosingPercentageAddsTipOfIt() {
    let draft = ReceiptDraft.fixture()

    draft.setTipPercentage(20)

    XCTAssertEqual(draft.tip, 6)
    XCTAssertEqual(draft.tipPercentage, 20)
  }

  func testChoosingPercentageMovesTotalThatAddedUp() {
    let draft = ReceiptDraft.fixture()

    draft.setTipPercentage(20)

    XCTAssertEqual(draft.total, 36)
  }

  func testChoosingCustomKeepsAmount() {
    let draft = ReceiptDraft.fixture()
    draft.setTipPercentage(20)

    draft.setTipPercentage(nil)

    XCTAssertNil(draft.tipPercentage)
    XCTAssertEqual(draft.tip, 6)
  }

  func testEnteringAmountEndsPercentage() {
    let draft = ReceiptDraft.fixture()
    draft.setTipPercentage(20)

    draft.tip = 5

    XCTAssertNil(draft.tipPercentage)
  }

  func testAddingTipAmountEndsPercentage() {
    let draft = ReceiptDraft.fixture()
    draft.setTipPercentage(20)

    draft.addAdjustment(.tip, amount: 6)

    XCTAssertNil(draft.tipPercentage)
  }

  func testRemovingTipEndsPercentage() {
    let draft = ReceiptDraft.fixture()
    draft.setTipPercentage(20)

    draft.removeAdjustment(.tip)

    XCTAssertNil(draft.tipPercentage)
  }

  func testReadTipIsAnAmount() {
    let draft = ReceiptDraft.fixture(tip: 6)

    XCTAssertNil(draft.tipPercentage)
  }

  func testPercentageTipFollowsTaxAboveIt() {
    let draft = ReceiptDraft.fixture(tax: 3, order: [.tax, .tip, .savings])
    draft.setTipPercentage(20)

    draft.tax = 4

    XCTAssertEqual(draft.tip, 6.80)
  }

  func testPercentageTipFollowingTaxMovesTotal() {
    let draft = ReceiptDraft.fixture(tax: 3, order: [.tax, .tip, .savings])
    draft.setTipPercentage(20)

    draft.tax = 4

    XCTAssertEqual(draft.total, 40.80)
  }

  func testPercentageTipFollowsSubtotal() {
    let draft = ReceiptDraft.fixture()
    draft.setTipPercentage(20)

    draft.setSubtotal(40)

    XCTAssertEqual(draft.tip, 8)
  }

  func testPercentageTipFollowsItemsWithoutSubtotal() {
    let draft = ReceiptDraft.fixture(subtotal: 0)
    draft.setTipPercentage(20)

    draft.items[1].lineTotal = 30

    XCTAssertEqual(draft.tip, 8)
  }

  func testPercentageTipFollowsSavingsAboveIt() {
    let draft = ReceiptDraft.fixture(order: [.tax, .savings, .tip])
    draft.setTipPercentage(20)

    draft.savings = 5

    XCTAssertEqual(draft.tip, 5)
  }

  func testPercentageTipFollowsCurrency() {
    let draft = ReceiptDraft.fixture(subtotal: 0)
    draft.items[0].lineTotal = 1015
    draft.items[1].lineTotal = 0
    draft.setTipPercentage(18)

    draft.currency = "JPY"

    XCTAssertEqual(draft.tip, 183)
  }

  func testPercentageStaysChosenAsBaseChanges() {
    let draft = ReceiptDraft.fixture(tax: 3, order: [.tax, .tip, .savings])
    draft.setTipPercentage(20)

    draft.tax = 4

    XCTAssertEqual(draft.tipPercentage, 20)
  }

  func testEnteredTipKeepsAmountAsBaseChanges() {
    let draft = ReceiptDraft.fixture(tax: 3, order: [.tax, .tip, .savings])
    draft.addAdjustment(.tip, amount: 6.60)

    draft.tax = 4

    XCTAssertEqual(draft.tip, 6.60)
  }

  func testPercentageOfZeroBaseStaysChosen() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 0])

    draft.setTipPercentage(20)

    XCTAssertEqual(draft.tipPercentage, 20)
    XCTAssertEqual(draft.tip, 0)
  }

  func testPercentagesRoundingAlikeStayDistinct() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 0.05])
    draft.setTipPercentage(18)

    draft.setTipPercentage(22)

    XCTAssertEqual(draft.tipPercentage, 22)
  }

  func testMovingTinyTipKeepsItsPercentage() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 0.1], tax: 10)
    draft.setTipPercentage(20)

    draft.setAdjustmentOrder([.tax, .tip, .savings])

    XCTAssertEqual(draft.tip, 2.02)
  }

  func testMovingEnteredTipAtPresetAmountKeepsIt() {
    let draft = ReceiptDraft.fixture(tax: 3)
    draft.addAdjustment(.tip, amount: 6)

    draft.setAdjustmentOrder([.tax, .tip, .savings])

    XCTAssertEqual(draft.tip, 6)
  }

  func testTipThatExplainsSavingsKeepsItsBase() {
    let draft = makeSavingsDraft()

    draft.setTipPercentage(18)

    XCTAssertEqual(draft.tip, 5.04)
    XCTAssertEqual(draft.tipBaseAmount, 28)
  }

  func testTipThatExplainsSavingsLeavesPrintedTotal() {
    let draft = makeSavingsDraft()

    draft.setTipPercentage(18)

    XCTAssertEqual(draft.total, 35.04)
  }

  func testTipThatExplainsSavingsBalancesReceipt() {
    let draft = makeSavingsDraft()

    draft.setTipPercentage(18)

    XCTAssertTrue(draft.balance.isBalanced)
  }

  func testTipThatExplainsSavingsKeepsItsBaseThroughEdits() {
    let draft = makeSavingsDraft()
    draft.setTipPercentage(18)

    draft.tax = 0

    XCTAssertEqual(draft.tip, 5.04)
    XCTAssertEqual(draft.total, 35.04)
  }

  func testTipThatExplainsSavingsIsCaptionedAsChosen() throws {
    let draft = makeSavingsDraft()
    draft.setTipPercentage(18)

    let caption = try XCTUnwrap(draft.tipCaption(for: draft.tip, percentage: 18))

    XCTAssertTrue(caption.hasPrefix(0.18.formatted(.percent.precision(.fractionLength(0...1)))))
  }

  func testTipOnSavingsInPricesFollowsTotal() {
    let draft = ReceiptDraft.fixture(
      subtotal: 0, savings: 2, total: 30, order: [.tax, .savings, .tip])

    draft.setTipPercentage(20)

    XCTAssertEqual(draft.tip, 6)
    XCTAssertTrue(draft.balance.isBalanced)
  }

  func testPresetOfChosenPercentageIsTheTip() throws {
    let draft = makeSavingsDraft()
    draft.setTipPercentage(18)

    let preset = try XCTUnwrap(draft.tipPresets.first { $0.percentage == 18 })

    XCTAssertEqual(preset.amount, draft.tip)
  }

  func testConfirmingTipPercentageStopsAsking() {
    let draft = ReceiptDraft.fixture()
    draft.askAboutMissingAdjustments()

    draft.confirmTip(percentage: 20)

    XCTAssertEqual(draft.tipPercentage, 20)
    XCTAssertFalse(draft.unconfirmedAdjustments.contains(.tip))
  }

  /// A receipt without a subtotal whose total is $7.04 over its items after savings, which an 18%
  /// tip after savings explains only if the savings were already in the item prices.
  func testTipBaseBeforeTaxIsSubtotal() {
    let draft = ReceiptDraft.fixture(subtotal: 32, tax: 3)

    XCTAssertEqual(draft.tipBaseAmount, 32)
  }

  func testTipBaseWithoutSubtotalIsItems() {
    let draft = ReceiptDraft.fixture(subtotal: 0, tax: 3)

    XCTAssertEqual(draft.tipBaseAmount, 30)
  }

  func testTipBelowTaxAddsTax() {
    let draft = ReceiptDraft.fixture(tax: 3, order: [.tax, .tip, .savings])

    XCTAssertEqual(draft.tipBaseAmount, 33)
  }

  func testTipAboveSavingsLeavesThemOut() {
    let draft = ReceiptDraft.fixture(tax: 3, savings: 2, order: [.tax, .tip, .savings])

    XCTAssertEqual(draft.tipBaseAmount, 33)
  }

  func testTipBelowSavingsTakesThemOff() {
    let draft = ReceiptDraft.fixture(tax: 3, savings: 2, order: [.tax, .savings, .tip])

    XCTAssertEqual(draft.tipBaseAmount, 31)
  }

  func testTipBelowSavingsOnlyTakesThemOffSubtotal() {
    let draft = ReceiptDraft.fixture(savings: 2, order: [.savings, .tip, .tax])

    XCTAssertEqual(draft.tipBaseAmount, 28)
  }

  func testTipBelowSavingsInSubtotalLeavesSubtotal() {
    let draft = ReceiptDraft.fixture(tax: 3, savings: 2, total: 33, order: [.tax, .savings, .tip])

    XCTAssertEqual(draft.tipBaseAmount, 33)
  }

  func testTipBaseLeavesOutTip() {
    let draft = ReceiptDraft.fixture(tax: 3, order: [.tax, .tip, .savings])
    draft.tip = 6

    XCTAssertEqual(draft.tipBaseAmount, 33)
  }

  func testTipAboveTaxIsBeforeTax() {
    XCTAssertFalse(ReceiptDraft.fixture(tax: 3).isTipAfterTax)
  }

  func testTipBelowTaxIsAfterTax() {
    XCTAssertTrue(ReceiptDraft.fixture(tax: 3, order: [.tax, .tip, .savings]).isTipAfterTax)
  }

  func testTipWithoutSavingsDoesNotNameThem() {
    XCTAssertNil(ReceiptDraft.fixture(tax: 3).isTipAfterSavings)
  }

  func testTipAboveSavingsTakenOffAfterSubtotalIsBeforeThem() {
    let draft = ReceiptDraft.fixture(tax: 3, savings: 2)

    XCTAssertEqual(draft.isTipAfterSavings, false)
  }

  func testTipAboveSavingsInSubtotalIsAfterThem() {
    let draft = ReceiptDraft.fixture(subtotal: 28, tax: 3, savings: 2, total: 31)

    XCTAssertEqual(draft.isTipAfterSavings, true)
  }

  func testTipBelowSavingsIsAfterThem() {
    let draft = ReceiptDraft.fixture(tax: 3, savings: 2, order: [.tax, .savings, .tip])

    XCTAssertEqual(draft.isTipAfterSavings, true)
  }

  func testMovingSuggestedTipBelowTaxKeepsItsPercentage() {
    let draft = ReceiptDraft.fixture(tax: 3)
    draft.setTipPercentage(20)

    draft.setAdjustmentOrder([.tax, .tip, .savings])

    XCTAssertEqual(draft.adjustmentOrder, [.tax, .tip, .savings])
    XCTAssertEqual(draft.tip, 6.60)
  }

  func testMovingSuggestedTipMovesTotal() {
    let draft = ReceiptDraft.fixture(tax: 3)
    draft.setTipPercentage(20)

    draft.setAdjustmentOrder([.tax, .tip, .savings])

    XCTAssertEqual(draft.total, 39.60)
  }

  func testMovingSuggestedTipAboveTaxKeepsItsPercentage() {
    let draft = ReceiptDraft.fixture(tax: 3, order: [.tax, .tip, .savings])
    draft.setTipPercentage(20)

    draft.setAdjustmentOrder([.tip, .tax, .savings])

    XCTAssertEqual(draft.tip, 6)
  }

  func testMovingSuggestedTipBelowSavingsKeepsItsPercentage() {
    let draft = ReceiptDraft.fixture(savings: 5)
    draft.setTipPercentage(20)

    draft.setAdjustmentOrder([.tax, .savings, .tip])

    XCTAssertEqual(draft.tip, 5)
  }

  func testMovingCustomTipKeepsItsAmount() {
    let draft = ReceiptDraft.fixture(tax: 3)
    draft.addAdjustment(.tip, amount: 5)

    draft.setAdjustmentOrder([.tax, .tip, .savings])

    XCTAssertEqual(draft.tip, 5)
  }

  func testMovingWithoutTipAddsNone() {
    let draft = ReceiptDraft.fixture(tax: 3)

    draft.setAdjustmentOrder([.tax, .tip, .savings])

    XCTAssertFalse(draft.adjustments.contains(.tip))
  }

  func testOrderMissingAnAdjustmentIsIgnored() {
    let draft = ReceiptDraft.fixture()

    draft.setAdjustmentOrder([.tax, .tip])

    XCTAssertEqual(draft.adjustmentOrder, [.tip, .tax, .savings])
  }

  func testOrderBeforeTaxListsTipFirst() {
    XCTAssertEqual(ReceiptTotalAdjustment.order(tipBase: .beforeTax), [.tip, .tax, .savings])
  }

  func testOrderAfterTaxListsTaxFirst() {
    XCTAssertEqual(ReceiptTotalAdjustment.order(tipBase: .afterTax), [.tax, .tip, .savings])
  }

  private func makeSavingsDraft() -> ReceiptDraft {
    ReceiptDraft.fixture(subtotal: 0, savings: 2, total: 35.04, order: [.tax, .savings, .tip])
  }
}
