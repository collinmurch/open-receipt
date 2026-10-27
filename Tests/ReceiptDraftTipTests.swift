import XCTest

@testable import open_receipt

@MainActor
final class ReceiptDraftTipTests: XCTestCase {
  func testChoosingPercentageAddsTipOfIt() {
    let draft = makeDraft()

    draft.setTipPercentage(20)

    XCTAssertEqual(draft.tip, 6, accuracy: 0.000_1)
    XCTAssertEqual(draft.tipPercentage, 20)
  }

  func testChoosingPercentageMovesTotalThatAddedUp() {
    let draft = makeDraft()

    draft.setTipPercentage(20)

    XCTAssertEqual(draft.total, 36, accuracy: 0.000_1)
  }

  func testChoosingCustomKeepsAmount() {
    let draft = makeDraft()
    draft.setTipPercentage(20)

    draft.setTipPercentage(nil)

    XCTAssertNil(draft.tipPercentage)
    XCTAssertEqual(draft.tip, 6, accuracy: 0.000_1)
  }

  func testEnteringAmountEndsPercentage() {
    let draft = makeDraft()
    draft.setTipPercentage(20)

    draft.tip = 5

    XCTAssertNil(draft.tipPercentage)
  }

  func testAddingTipAmountEndsPercentage() {
    let draft = makeDraft()
    draft.setTipPercentage(20)

    draft.addAdjustment(.tip, amount: 6)

    XCTAssertNil(draft.tipPercentage)
  }

  func testRemovingTipEndsPercentage() {
    let draft = makeDraft()
    draft.setTipPercentage(20)

    draft.removeAdjustment(.tip)

    XCTAssertNil(draft.tipPercentage)
  }

  func testReadTipIsAnAmount() {
    let draft = makeDraft(tip: 6, total: 36)

    XCTAssertNil(draft.tipPercentage)
  }

  func testPercentageTipFollowsTaxAboveIt() {
    let draft = makeDraft(tax: 3, total: 33, order: [.tax, .tip, .savings])
    draft.setTipPercentage(20)

    draft.tax = 4

    XCTAssertEqual(draft.tip, 6.80, accuracy: 0.000_1)
  }

  func testPercentageTipFollowingTaxMovesTotal() {
    let draft = makeDraft(tax: 3, total: 33, order: [.tax, .tip, .savings])
    draft.setTipPercentage(20)

    draft.tax = 4

    XCTAssertEqual(draft.total, 40.80, accuracy: 0.000_1)
  }

  func testPercentageTipFollowsSubtotal() {
    let draft = makeDraft()
    draft.setTipPercentage(20)

    draft.setSubtotal(40)

    XCTAssertEqual(draft.tip, 8, accuracy: 0.000_1)
  }

  func testPercentageTipFollowsItemsWithoutSubtotal() {
    let draft = makeDraft(subtotal: 0)
    draft.setTipPercentage(20)

    draft.items[1].lineTotal = 30

    XCTAssertEqual(draft.tip, 8, accuracy: 0.000_1)
  }

  func testPercentageTipFollowsSavingsAboveIt() {
    let draft = makeDraft(order: [.tax, .savings, .tip])
    draft.setTipPercentage(20)

    draft.savings = 5

    XCTAssertEqual(draft.tip, 5, accuracy: 0.000_1)
  }

  func testPercentageTipFollowsCurrency() {
    let draft = makeDraft(subtotal: 0)
    draft.items[0].lineTotal = 1015
    draft.items[1].lineTotal = 0
    draft.setTipPercentage(18)

    draft.currency = "JPY"

    XCTAssertEqual(draft.tip, 183)
  }

  func testPercentageStaysChosenAsBaseChanges() {
    let draft = makeDraft(tax: 3, total: 33, order: [.tax, .tip, .savings])
    draft.setTipPercentage(20)

    draft.tax = 4

    XCTAssertEqual(draft.tipPercentage, 20)
  }

  func testEnteredTipKeepsAmountAsBaseChanges() {
    let draft = makeDraft(tax: 3, total: 33, order: [.tax, .tip, .savings])
    draft.addAdjustment(.tip, amount: 6.60)

    draft.tax = 4

    XCTAssertEqual(draft.tip, 6.60, accuracy: 0.000_1)
  }

  func testPercentageOfZeroBaseStaysChosen() {
    let draft = makeDraft(subtotal: 0, total: 0, items: [0])

    draft.setTipPercentage(20)

    XCTAssertEqual(draft.tipPercentage, 20)
    XCTAssertEqual(draft.tip, 0)
  }

  func testPercentagesRoundingAlikeStayDistinct() {
    let draft = makeDraft(subtotal: 0.05, total: 0.05, items: [0.05])
    draft.setTipPercentage(18)

    draft.setTipPercentage(22)

    XCTAssertEqual(draft.tipPercentage, 22)
  }

  func testMovingTinyTipKeepsItsPercentage() {
    let draft = makeDraft(subtotal: 0.10, tax: 10, total: 10.10, items: [0.10])
    draft.setTipPercentage(20)

    draft.setAdjustmentOrder([.tax, .tip, .savings])

    XCTAssertEqual(draft.tip, 2.02, accuracy: 0.000_1)
  }

  func testMovingEnteredTipAtPresetAmountKeepsIt() {
    let draft = makeDraft(tax: 3, total: 33)
    draft.addAdjustment(.tip, amount: 6)

    draft.setAdjustmentOrder([.tax, .tip, .savings])

    XCTAssertEqual(draft.tip, 6, accuracy: 0.000_1)
  }

  func testTipThatExplainsSavingsKeepsItsBase() {
    let draft = makeSavingsDraft()

    draft.setTipPercentage(18)

    XCTAssertEqual(draft.tip, 5.04, accuracy: 0.000_1)
    XCTAssertEqual(draft.tipBaseAmount, 28, accuracy: 0.000_1)
  }

  func testTipThatExplainsSavingsLeavesPrintedTotal() {
    let draft = makeSavingsDraft()

    draft.setTipPercentage(18)

    XCTAssertEqual(draft.total, 35.04, accuracy: 0.000_1)
  }

  func testTipThatExplainsSavingsKeepsItsBaseThroughEdits() {
    let draft = makeSavingsDraft()
    draft.setTipPercentage(18)

    draft.tax = 0

    XCTAssertEqual(draft.tip, 5.04, accuracy: 0.000_1)
    XCTAssertEqual(draft.total, 35.04, accuracy: 0.000_1)
  }

  func testTipThatExplainsSavingsIsCaptionedAsChosen() throws {
    let draft = makeSavingsDraft()
    draft.setTipPercentage(18)

    let caption = try XCTUnwrap(draft.tipCaption(for: draft.tip, percentage: 18))

    XCTAssertTrue(caption.hasPrefix(0.18.formatted(.percent.precision(.fractionLength(0...1)))))
  }

  func testTipOnSavingsInPricesFollowsTotal() {
    let draft = makeDraft(subtotal: 0, savings: 2, total: 30, order: [.tax, .savings, .tip])

    draft.setTipPercentage(20)

    XCTAssertEqual(draft.tip, 6, accuracy: 0.000_1)
    XCTAssertTrue(draft.balance.isBalanced)
  }

  func testPresetOfChosenPercentageIsTheTip() throws {
    let draft = makeSavingsDraft()
    draft.setTipPercentage(18)

    let preset = try XCTUnwrap(draft.tipPresets.first { $0.percentage == 18 })

    XCTAssertEqual(preset.amount, draft.tip, accuracy: 0.000_1)
  }

  func testConfirmingTipPercentageStopsAsking() {
    let draft = makeDraft()
    draft.askAboutMissingAdjustments()

    draft.confirmTip(percentage: 20)

    XCTAssertEqual(draft.tipPercentage, 20)
    XCTAssertFalse(draft.unconfirmedAdjustments.contains(.tip))
  }

  /// A receipt without a subtotal whose total is $7.04 over its items after savings, which an 18%
  /// tip after savings explains only if the savings were already in the item prices.
  private func makeSavingsDraft() -> ReceiptDraft {
    makeDraft(subtotal: 0, savings: 2, total: 35.04, order: [.tax, .savings, .tip])
  }

  private func makeDraft(
    subtotal: Double = 30,
    tax: Double = 0,
    tip: Double = 0,
    savings: Double = 0,
    total: Double = 30,
    items: [Double] = [10, 20],
    order: [ReceiptTotalAdjustment] = [.tip, .tax, .savings]
  ) -> ReceiptDraft {
    ReceiptDraft(
      receipt: ParsedReceipt(
        merchantName: "Cafe",
        subtotal: subtotal,
        tax: tax,
        tip: tip,
        savings: savings,
        total: total,
        currency: "USD",
        items: items.map { ReceiptItem(description: "Item", quantity: 1, lineTotal: $0) }),
      adjustmentOrder: order)
  }
}
