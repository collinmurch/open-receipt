import XCTest

@testable import open_receipt

final class ReceiptItemSweepTests: XCTestCase {
  private let alex = UUID()
  private let jordan = UUID()

  func testSweepNeedsSelectedPeople() {
    let items = makeItems(count: 2)

    XCTAssertNil(ReceiptItemSweep(startingAt: items[0].id, in: items, participantIDs: []))
  }

  func testSweepNeedsKnownStartingItem() {
    let items = makeItems(count: 2)

    XCTAssertNil(ReceiptItemSweep(startingAt: UUID(), in: items, participantIDs: [alex]))
  }

  func testSweepStartingOnUnassignedItemAssigns() throws {
    let items = makeItems(count: 2)

    let sweep = try XCTUnwrap(
      ReceiptItemSweep(startingAt: items[0].id, in: items, participantIDs: [alex]))

    XCTAssertTrue(sweep.assigns)
    XCTAssertEqual(sweep.applied(to: items)[0].participantIDs, [alex])
  }

  func testSweepStartingOnAssignedItemRemoves() throws {
    var items = makeItems(count: 2)
    items[0].participantIDs = [alex, jordan]

    let sweep = try XCTUnwrap(
      ReceiptItemSweep(startingAt: items[0].id, in: items, participantIDs: [alex]))

    XCTAssertFalse(sweep.assigns)
    XCTAssertEqual(sweep.applied(to: items)[0].participantIDs, [jordan])
  }

  func testSweepStartingOnPartlyAssignedItemAssigns() throws {
    var items = makeItems(count: 1)
    items[0].participantIDs = [alex]

    let sweep = try XCTUnwrap(
      ReceiptItemSweep(startingAt: items[0].id, in: items, participantIDs: [alex, jordan]))

    XCTAssertTrue(sweep.assigns)
    XCTAssertEqual(sweep.applied(to: items)[0].participantIDs, [alex, jordan])
  }

  func testExtendingCoversEveryItemBetween() throws {
    let items = makeItems(count: 4)
    var sweep = try XCTUnwrap(
      ReceiptItemSweep(startingAt: items[0].id, in: items, participantIDs: [alex]))

    XCTAssertTrue(sweep.extend(to: items[2].id))

    XCTAssertEqual(Array(sweep.coveredItemIDs), items[0...2].map(\.id))
    XCTAssertEqual(
      sweep.applied(to: items).map(\.participantIDs), [[alex], [alex], [alex], []])
  }

  func testExtendingUpwardCoversItemsAbove() throws {
    let items = makeItems(count: 3)
    var sweep = try XCTUnwrap(
      ReceiptItemSweep(startingAt: items[2].id, in: items, participantIDs: [alex]))

    _ = sweep.extend(to: items[0].id)

    XCTAssertEqual(Array(sweep.coveredItemIDs), items.map(\.id))
  }

  func testExtendingToSameItemReportsNoChange() throws {
    let items = makeItems(count: 2)
    var sweep = try XCTUnwrap(
      ReceiptItemSweep(startingAt: items[0].id, in: items, participantIDs: [alex]))

    XCTAssertFalse(sweep.extend(to: items[0].id))
  }

  func testExtendingToUnknownItemReportsNoChange() throws {
    let items = makeItems(count: 2)
    var sweep = try XCTUnwrap(
      ReceiptItemSweep(startingAt: items[0].id, in: items, participantIDs: [alex]))

    XCTAssertFalse(sweep.extend(to: UUID()))
    XCTAssertEqual(Array(sweep.coveredItemIDs), [items[0].id])
  }

  func testPullingBackRestoresUncoveredItems() throws {
    var items = makeItems(count: 3)
    items[2].participantIDs = [jordan]
    var sweep = try XCTUnwrap(
      ReceiptItemSweep(startingAt: items[0].id, in: items, participantIDs: [alex]))
    _ = sweep.extend(to: items[2].id)
    let swept = sweep.applied(to: items)

    _ = sweep.extend(to: items[0].id)

    XCTAssertEqual(
      sweep.applied(to: swept).map(\.participantIDs), [[alex], [], [jordan]])
  }

  func testRemovingKeepsOtherPeople() throws {
    var items = makeItems(count: 2)
    items[0].participantIDs = [alex]
    items[1].participantIDs = [alex, jordan]
    var sweep = try XCTUnwrap(
      ReceiptItemSweep(startingAt: items[0].id, in: items, participantIDs: [alex]))

    _ = sweep.extend(to: items[1].id)

    XCTAssertEqual(sweep.applied(to: items).map(\.participantIDs), [[], [jordan]])
  }

  func testItemsAddedAfterStartAreLeftAlone() throws {
    let items = makeItems(count: 1)
    let sweep = try XCTUnwrap(
      ReceiptItemSweep(startingAt: items[0].id, in: items, participantIDs: [alex]))
    let added = makeItems(count: 1)[0]

    XCTAssertEqual(sweep.applied(to: items + [added]).last, added)
  }

  @MainActor
  func testDraftApplyAssignsSweptItems() throws {
    let draft = ReceiptDraft(
      receipt: ParsedReceipt(
        items: [
          ReceiptItem(description: "Tea", quantity: 1, lineTotal: 3),
          ReceiptItem(description: "Scone", quantity: 1, lineTotal: 4),
        ]))
    let ownerID = try XCTUnwrap(draft.currentUser?.id)
    var sweep = try XCTUnwrap(
      ReceiptItemSweep(startingAt: draft.items[0].id, in: draft.items, participantIDs: [ownerID]))
    _ = sweep.extend(to: draft.items[1].id)

    draft.apply(sweep)

    XCTAssertEqual(draft.items.map(\.participantIDs), [[ownerID], [ownerID]])
  }

  @MainActor
  func testDraftReapplyingSameSweepKeepsRevision() throws {
    let draft = ReceiptDraft(
      receipt: ParsedReceipt(items: [ReceiptItem(description: "Tea", quantity: 1, lineTotal: 3)]))
    let ownerID = try XCTUnwrap(draft.currentUser?.id)
    let sweep = try XCTUnwrap(
      ReceiptItemSweep(startingAt: draft.items[0].id, in: draft.items, participantIDs: [ownerID]))
    draft.apply(sweep)
    let revision = draft.persistenceRevision

    draft.apply(sweep)

    XCTAssertEqual(draft.persistenceRevision, revision)
  }

  private func makeItems(count: Int) -> [ReceiptDraftItem] {
    (0..<count).map { index in
      ReceiptDraftItem(
        id: UUID(), description: "Item \(index)", quantity: 1, lineTotal: 1, participantIDs: [])
    }
  }
}
