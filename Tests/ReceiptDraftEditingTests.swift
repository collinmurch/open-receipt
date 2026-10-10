import XCTest

@testable import open_receipt

@MainActor
final class ReceiptDraftEditingTests: XCTestCase {
  func testPurchaseDateReadsStoredReceiptDate() {
    let draft = makeDraft()

    let components = ReceiptLocalDate.calendar.dateComponents(
      [.year, .month, .day], from: draft.purchaseDate)

    XCTAssertEqual(components.year, 2026)
    XCTAssertEqual(components.month, 8)
    XCTAssertEqual(components.day, 11)
  }

  func testPurchaseDateWritesStorageFormat() throws {
    let draft = makeDraft()
    let selectedDate = try XCTUnwrap(
      ReceiptLocalDate.calendar.date(from: DateComponents(year: 2027, month: 2, day: 3)))

    draft.purchaseDate = selectedDate

    XCTAssertEqual(draft.date, "2027-02-03")
  }

  func testNormalizeTrimsEditableText() {
    let draft = makeDraft()
    draft.merchantName = "  Market  "
    draft.date = "  2026-08-11  "
    draft.currency = " eur "
    draft.items[0].description = "  Tea  "

    draft.normalizeEditableFields()

    XCTAssertEqual(draft.merchantName, "Market")
    XCTAssertEqual(draft.date, "2026-08-11")
    XCTAssertEqual(draft.currency, "EUR")
    XCTAssertEqual(draft.items[0].description, "Tea")
  }

  func testAddItemUsesSafeDefaults() throws {
    let draft = makeDraft()

    let id = draft.addItem()

    let item = try XCTUnwrap(draft.items.first { $0.id == id })
    XCTAssertEqual(item.description, "")
    XCTAssertEqual(item.quantity, 1)
    XCTAssertEqual(item.lineTotal, 0)
    XCTAssertTrue(item.participantIDs.isEmpty)
  }

  func testRemoveItemRemovesOnlySelectedItem() {
    let draft = makeDraft()
    let addedID = draft.addItem()

    draft.removeItem(id: addedID)

    XCTAssertEqual(draft.items.count, 1)
    XCTAssertEqual(draft.items[0].description, "Coffee")
  }

  func testSplitItemCreatesRequestedNumberOfItems() {
    let draft = makeDraft()

    draft.splitItem(id: draft.items[0].id, into: 3)

    XCTAssertEqual(draft.items.count, 3)
  }

  func testSplitItemNamesEachPart() {
    let draft = makeDraft()

    draft.splitItem(id: draft.items[0].id, into: 3)

    XCTAssertEqual(
      draft.items.map(\.description), ["Coffee (1/3)", "Coffee (2/3)", "Coffee (3/3)"])
  }

  func testSplitItemDividesQuantity() {
    let draft = makeDraft()
    draft.items[0].quantity = 3

    draft.splitItem(id: draft.items[0].id, into: 3)

    XCTAssertEqual(draft.items.map(\.quantity), [1, 1, 1])
  }

  func testSplitSingleQuantityItemProducesFractionalQuantities() {
    let draft = makeDraft()

    draft.splitItem(id: draft.items[0].id, into: 2)

    XCTAssertEqual(draft.items.map(\.quantity), [0.5, 0.5])
  }

  func testSplitItemDividesLineTotalEvenly() {
    let draft = makeDraft()

    draft.splitItem(id: draft.items[0].id, into: 2)

    XCTAssertEqual(draft.items.map(\.lineTotal), [2.25, 2.25])
  }

  func testSplitItemAssignsLeftoverCentsToFirstItems() {
    let draft = makeDraft()
    draft.items[0].lineTotal = 10

    draft.splitItem(id: draft.items[0].id, into: 3)

    XCTAssertEqual(draft.items.map(\.lineTotal), [3.34, 3.33, 3.33])
  }

  func testSplitNegativeItemPreservesTotal() {
    let draft = makeDraft()
    draft.items[0].lineTotal = -1

    draft.splitItem(id: draft.items[0].id, into: 3)

    XCTAssertEqual(draft.items.map(\.lineTotal), [-0.34, -0.33, -0.33])
  }

  func testSplitItemKeepsParticipantAssignments() {
    let draft = makeDraft()
    let participantID = draft.participants[0].id
    draft.items[0].participantIDs = [participantID]

    draft.splitItem(id: draft.items[0].id, into: 2)

    XCTAssertTrue(draft.items.allSatisfy { $0.participantIDs == [participantID] })
  }

  func testSplitItemKeepsPositionAmongItems() {
    let draft = makeDraft()
    let addedID = draft.addItem()
    draft.items[1].description = "Bagel"

    draft.splitItem(id: draft.items[0].id, into: 2)

    XCTAssertEqual(draft.items.map(\.description), ["Coffee (1/2)", "Coffee (2/2)", "Bagel"])
    XCTAssertEqual(draft.items.last?.id, addedID)
  }

  func testSplitItemIgnoresCountBelowTwo() {
    let draft = makeDraft()

    let ids = draft.splitItem(id: draft.items[0].id, into: 1)

    XCTAssertTrue(ids.isEmpty)
    XCTAssertEqual(draft.items.map(\.description), ["Coffee"])
  }

  func testAddAdjustmentIncludesZeroValue() {
    let draft = makeDraft()

    draft.adjustments.add(.tax)

    XCTAssertTrue(draft.adjustments.contains(.tax))
    XCTAssertEqual(draft.tax, 0)
  }

  func testRemoveAdjustmentClearsItsValue() {
    let draft = makeDraft()
    draft.adjustments.add(.tip)
    draft.tip = 5

    draft.adjustments.remove(.tip)

    XCTAssertFalse(draft.adjustments.contains(.tip))
    XCTAssertEqual(draft.tip, 0)
  }

  func testEmptyItemNameProducesValidationIssue() {
    let draft = makeDraft()
    draft.items[0].description = "  "

    XCTAssertTrue(
      draft.issues.contains(.missingItemDescription(draft.items[0].id)))
  }

  func testNonPositiveQuantityProducesValidationIssue() {
    let draft = makeDraft()
    draft.items[0].quantity = 0

    XCTAssertTrue(draft.issues.contains(.invalidItemQuantity(draft.items[0].id)))
  }

  func testValidItemHasNoValidationIssues() {
    let draft = makeDraft()

    XCTAssertTrue(draft.items[0].issues.isEmpty)
  }

  func testItemReportsEachInvalidField() {
    var item = makeDraft().items[0]
    item.description = ""
    item.quantity = -1
    item.lineTotal = .nan

    XCTAssertEqual(
      item.issues,
      [
        .missingItemDescription(item.id), .invalidItemQuantity(item.id),
        .invalidItemTotal(item.id),
      ])
  }

  func testInvalidCurrencyProducesValidationIssue() {
    let draft = makeDraft()
    draft.currency = "US"

    XCTAssertTrue(draft.issues.contains(.invalidCurrency))
  }

  func testItemIssuesAreShownBesideTheirItem() {
    let draft = makeDraft()
    draft.items[0].description = ""
    let id = draft.items[0].id

    XCTAssertEqual(draft.issues(at: .item(id)), [.missingItemDescription(id)])
  }

  func testItemIssuesStayOffOtherRows() {
    let draft = makeDraft()
    draft.items[0].description = ""

    XCTAssertTrue(draft.issues(at: .amount(.total)).isEmpty)
  }

  func testInvalidSubtotalIsShownBesideSubtotal() {
    let draft = makeDraft()
    draft.subtotal = .nan

    XCTAssertEqual(draft.issues(at: .amount(.subtotal)), [.invalidAmount(.subtotal)])
  }

  func testNegativeTaxIsShownBesideTax() {
    let draft = makeDraft()
    draft.tax = -1

    XCTAssertEqual(
      draft.issues(at: .amount(.adjustment(.tax))), [.negativeAmount(.adjustment(.tax))])
  }

  func testRemovedAdjustmentHasNoIssues() {
    let draft = makeDraft()
    draft.tip = -1
    draft.adjustments.remove(.tip)

    XCTAssertTrue(draft.issues(at: .amount(.adjustment(.tip))).isEmpty)
  }

  func testZeroTotalIsShownBesideTotal() {
    let draft = makeDraft()
    draft.total = 0

    XCTAssertEqual(draft.issues(at: .amount(.total)), [.zeroTotal])
  }

  func testInvalidCurrencyIsShownBesideCurrency() {
    let draft = makeDraft()
    draft.currency = "US"

    XCTAssertEqual(draft.issues(at: .currency), [.invalidCurrency])
  }

  func testExpectedTotalUsesItemsAndSubtractsSavings() {
    let draft = makeDraft()
    draft.tax = 1
    draft.tip = 2
    draft.savings = 0.50

    XCTAssertEqual(draft.expectedTotal, 7, accuracy: 0.000_1)
  }

  func testSavingsPercentageUpdatesDollarSavings() {
    let draft = makeDraft()

    draft.savingsPercentage = 20

    XCTAssertEqual(draft.savings, 0.90, accuracy: 0.000_1)
    XCTAssertEqual(draft.savingsPercentage, 20, accuracy: 0.000_1)
  }

  func testTipPercentageUpdatesDollarTip() {
    let draft = makeDraft()

    draft.tipPercentage = 20

    XCTAssertEqual(draft.tip, 0.90, accuracy: 0.000_1)
    XCTAssertEqual(draft.tipPercentage, 20, accuracy: 0.000_1)
  }

  func testTipPercentageRoundsTipToCents() {
    let draft = makeDraft()

    draft.tipPercentage = 18.5

    XCTAssertEqual(draft.tip, 0.83)
  }

  func testSavingsPercentageRoundsSavingsToCents() {
    let draft = makeDraft()

    draft.savingsPercentage = 18.5

    XCTAssertEqual(draft.savings, 0.83)
  }

  func testTipPercentageRoundsTipToWholeYen() {
    let draft = makeDraft()
    draft.currency = "JPY"
    draft.items[0].lineTotal = 1000

    draft.tipPercentage = 18.25

    XCTAssertEqual(draft.tip, 183)
  }

  func testSplitItemInYenUsesWholeYen() {
    let draft = makeDraft()
    draft.currency = "JPY"
    draft.items[0].lineTotal = 1000

    draft.splitItem(id: draft.items[0].id, into: 3)

    XCTAssertEqual(draft.items.map(\.lineTotal), [334, 333, 333])
  }

  func testFixTotalRoundsToCents() {
    let draft = makeDraft()
    draft.adjustments.add(.tip)
    draft.tip = 0.8125

    draft.fixTotal()

    XCTAssertEqual(draft.total, 5.31)
  }

  func testTotalWithinHalfACentNeedsNoCorrection() {
    let draft = makeDraft()
    draft.adjustments.add(.tip)
    draft.tip = 0.8125
    draft.total = 5.31

    XCTAssertNil(draft.corrections.total)
  }

  func testFixTotalMatchesExpectedTotal() {
    let draft = makeDraft()
    draft.adjustments.add(.tax)
    draft.tax = 0.40
    XCTAssertEqual(draft.corrections.total ?? 0, 4.90, accuracy: 0.000_1)

    draft.fixTotal()

    XCTAssertEqual(draft.total, 4.90, accuracy: 0.000_1)
    XCTAssertNil(draft.corrections.total)
  }

  func testReceiptMutationAdvancesPersistenceRevision() {
    let draft = makeDraft()
    let revision = draft.persistenceRevision

    draft.merchantName = "Market"

    XCTAssertGreaterThan(draft.persistenceRevision, revision)
  }

  func testNormalizingCleanFieldsDoesNotAdvancePersistenceRevision() {
    let draft = makeDraft()
    let revision = draft.persistenceRevision

    draft.normalizeEditableFields()

    XCTAssertEqual(draft.persistenceRevision, revision)
  }

  private func makeDraft() -> ReceiptDraft {
    ReceiptDraft(
      receipt: ParsedReceipt(
        merchantName: "Cafe",
        date: "2026-08-11",
        subtotal: 4.50,
        total: 4.50,
        currency: "USD",
        items: [ReceiptItem(description: "Coffee", quantity: 1, lineTotal: 4.50)]))
  }
}
