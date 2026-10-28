import XCTest

@testable import open_receipt

@MainActor
final class ReceiptDraftEditingTests: XCTestCase {
  func testPurchaseDateReadsStoredReceiptDate() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    let components = ReceiptLocalDate.calendar.dateComponents(
      [.year, .month, .day], from: draft.purchaseDate)

    XCTAssertEqual(components.year, 2026)
    XCTAssertEqual(components.month, 8)
    XCTAssertEqual(components.day, 11)
  }

  func testPurchaseDateWritesStorageFormat() throws {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    let selectedDate = try XCTUnwrap(
      ReceiptLocalDate.calendar.date(from: DateComponents(year: 2027, month: 2, day: 3)))

    draft.purchaseDate = selectedDate

    XCTAssertEqual(draft.date, "2027-02-03")
  }

  func testNormalizeTrimsEditableText() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
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
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    let id = draft.addItem()

    let item = try XCTUnwrap(draft.items.first { $0.id == id })
    XCTAssertEqual(item.description, "")
    XCTAssertEqual(item.quantity, 1)
    XCTAssertEqual(item.lineTotal, 0)
    XCTAssertTrue(item.participantIDs.isEmpty)
  }

  func testRemoveItemRemovesOnlySelectedItem() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    let addedID = draft.addItem()

    draft.removeItem(id: addedID)

    XCTAssertEqual(draft.items.count, 1)
    XCTAssertEqual(draft.items[0].description, "Coffee")
  }

  func testSplitItemCreatesRequestedNumberOfItems() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    draft.splitItem(id: draft.items[0].id, into: 3)

    XCTAssertEqual(draft.items.count, 3)
  }

  func testSplitItemNamesEachPart() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    draft.splitItem(id: draft.items[0].id, into: 3)

    XCTAssertEqual(
      draft.items.map(\.description), ["Coffee (1/3)", "Coffee (2/3)", "Coffee (3/3)"])
  }

  func testSplitItemDividesQuantity() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.items[0].quantity = 3

    draft.splitItem(id: draft.items[0].id, into: 3)

    XCTAssertEqual(draft.items.map(\.quantity), [1, 1, 1])
  }

  func testSplitSingleQuantityItemProducesFractionalQuantities() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    draft.splitItem(id: draft.items[0].id, into: 2)

    XCTAssertEqual(draft.items.map(\.quantity), [0.5, 0.5])
  }

  func testSplitItemDividesLineTotalEvenly() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    draft.splitItem(id: draft.items[0].id, into: 2)

    XCTAssertEqual(draft.items.map(\.lineTotal), [2.25, 2.25])
  }

  func testSplitItemAssignsLeftoverCentsToFirstItems() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.items[0].lineTotal = 10

    draft.splitItem(id: draft.items[0].id, into: 3)

    XCTAssertEqual(draft.items.map(\.lineTotal), [3.34, 3.33, 3.33])
  }

  func testSplitNegativeItemPreservesTotal() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.items[0].lineTotal = -1

    draft.splitItem(id: draft.items[0].id, into: 3)

    XCTAssertEqual(draft.items.map(\.lineTotal), [-0.34, -0.33, -0.33])
  }

  func testSplitItemKeepsParticipantAssignments() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    let participantID = draft.ownerID
    draft.items[0].participantIDs = [participantID]

    draft.splitItem(id: draft.items[0].id, into: 2)

    XCTAssertTrue(draft.items.allSatisfy { $0.participantIDs == [participantID] })
  }

  func testSplitItemKeepsPositionAmongItems() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    let addedID = draft.addItem()
    draft.items[1].description = "Bagel"

    draft.splitItem(id: draft.items[0].id, into: 2)

    XCTAssertEqual(draft.items.map(\.description), ["Coffee (1/2)", "Coffee (2/2)", "Bagel"])
    XCTAssertEqual(draft.items.last?.id, addedID)
  }

  func testSplitItemIgnoresCountBelowTwo() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    let ids = draft.splitItem(id: draft.items[0].id, into: 1)

    XCTAssertTrue(ids.isEmpty)
    XCTAssertEqual(draft.items.map(\.description), ["Coffee"])
  }

  func testAddAdjustmentIncludesZeroValue() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    draft.addAdjustment(.tax)

    XCTAssertTrue(draft.adjustments.contains(.tax))
    XCTAssertEqual(draft.tax, 0)
  }

  func testRemoveAdjustmentClearsItsValue() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.addAdjustment(.tip)
    draft.tip = 5

    draft.removeAdjustment(.tip)

    XCTAssertFalse(draft.adjustments.contains(.tip))
    XCTAssertEqual(draft.tip, 0)
  }

  func testSavingsPercentageUpdatesDollarSavings() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    draft.savingsPercentage = 20

    XCTAssertEqual(draft.savings, 0.90)
    XCTAssertEqual(draft.savingsPercentage, 20)
  }

  func testSavingsPercentageRoundsSavingsToCents() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    draft.savingsPercentage = 18.5

    XCTAssertEqual(draft.savings, 0.83)
  }

  func testSavingsPercentageIsOfPrintedSubtotal() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.setSubtotal(10)

    draft.savingsPercentage = 20

    XCTAssertEqual(draft.savings, 2)
  }

  func testSavingsPercentageIsAtMostAll() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    draft.savingsPercentage = 150

    XCTAssertEqual(draft.savings, 4.50)
  }

  func testSavingsPercentageIsNeverNegative() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])

    draft.savingsPercentage = -10

    XCTAssertEqual(draft.savings, 0)
  }

  func testSplitItemInYenUsesWholeYen() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    draft.currency = "JPY"
    draft.items[0].lineTotal = 1000

    draft.splitItem(id: draft.items[0].id, into: 3)

    XCTAssertEqual(draft.items.map(\.lineTotal), [334, 333, 333])
  }

  func testReceiptMutationAdvancesPersistenceRevision() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    let revision = draft.persistenceRevision

    draft.merchantName = "Market"

    XCTAssertGreaterThan(draft.persistenceRevision, revision)
  }

  func testNormalizingCleanFieldsDoesNotAdvancePersistenceRevision() {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 4.5])
    let revision = draft.persistenceRevision

    draft.normalizeEditableFields()

    XCTAssertEqual(draft.persistenceRevision, revision)
  }
}
