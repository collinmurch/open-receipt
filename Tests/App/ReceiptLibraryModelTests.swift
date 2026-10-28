import XCTest

@testable import open_receipt

@MainActor
final class ReceiptLibraryModelTests: XCTestCase {
  func testSuccessfulDeleteRemovesReceipt() async {
    let receipt = ReceiptSummary.fixture()
    let model = makeModel(storage: makeStorage(receipts: [receipt]))
    await model.load()

    await model.delete(receipt)

    XCTAssertTrue(model.receipts.isEmpty)
    XCTAssertNil(model.errorDescription)
  }

  func testFailedDeleteRestoresReceipt() async {
    let receipt = ReceiptSummary.fixture()
    let model = makeModel(
      storage: makeStorage(receipts: [receipt], deleteError: .deleteFailed))
    await model.load()

    await model.delete(receipt)

    XCTAssertEqual(model.receipts, [receipt])
    XCTAssertNotNil(model.errorDescription)
  }

  func testDeletingUnlistedReceiptDeletesStoredReceipt() async {
    let model = makeModel(storage: makeStorage(receipts: []))
    await model.load()

    await model.delete(ReceiptSummary.fixture())

    XCTAssertTrue(model.receipts.isEmpty)
    XCTAssertNil(model.errorDescription)
  }

  func testFailedDeleteOfUnlistedReceiptShowsError() async {
    let model = makeModel(
      storage: makeStorage(receipts: [], deleteError: .deleteFailed))
    await model.load()

    await model.delete(ReceiptSummary.fixture())

    XCTAssertNotNil(model.errorDescription)
  }

  func testLoadGroupsReceiptsIntoSections() async {
    let receipt = ReceiptSummary.fixture()
    let model = makeModel(storage: makeStorage(receipts: [receipt]))

    await model.load()

    XCTAssertEqual(model.sections.map(\.id), ["2026-08-01"])
    XCTAssertEqual(model.sections.first?.receipts, [receipt])
  }

  func testDeleteRemovesReceiptFromSections() async {
    let receipt = ReceiptSummary.fixture()
    let model = makeModel(storage: makeStorage(receipts: [receipt]))
    await model.load()

    await model.delete(receipt)

    XCTAssertTrue(model.sections.isEmpty)
  }

  func testFailedDeleteRestoresReceiptToSections() async {
    let receipt = ReceiptSummary.fixture()
    let model = makeModel(
      storage: makeStorage(receipts: [receipt], deleteError: .deleteFailed))
    await model.load()

    await model.delete(receipt)

    XCTAssertEqual(model.sections.first?.receipts, [receipt])
  }

  func testLoadIncludesRecentlyDeletedReceipts() async {
    let deletedReceipt = makeDeletedSummary()
    let model = makeModel(
      storage: makeStorage(receipts: [], deletedReceipts: [deletedReceipt]))

    await model.load()

    XCTAssertEqual(model.deletedReceipts, [deletedReceipt])
  }

  func testFailedRestoreKeepsRecentlyDeletedReceipt() async {
    let deletedReceipt = makeDeletedSummary()
    let model = makeModel(
      storage: makeStorage(
        receipts: [],
        deletedReceipts: [deletedReceipt],
        restoreError: .restoreFailed))
    await model.load()

    await model.restore(deletedReceipt)

    XCTAssertEqual(model.deletedReceipts, [deletedReceipt])
    XCTAssertNotNil(model.errorDescription)
  }

  func testSuccessfulEmptyTrashClearsRecentlyDeletedReceipts() async {
    let deletedReceipt = makeDeletedSummary()
    let model = makeModel(
      storage: makeStorage(receipts: [], deletedReceipts: [deletedReceipt]))
    await model.load()

    await model.emptyTrash()

    XCTAssertTrue(model.deletedReceipts.isEmpty)
    XCTAssertNil(model.errorDescription)
  }

  func testTrashPurgeCheckIsLimitedToOncePerDay() async {
    let counter = CallCounter()
    let start = Date(timeIntervalSince1970: 1_000_000)
    let model = makeModel(
      storage: makeStorage(
        receipts: [],
        purgeExpiredTrash: { _ in counter.increment() }))

    await model.refreshTrashIfNeeded(now: start)
    await model.refreshTrashIfNeeded(now: start.addingTimeInterval(60 * 60))
    await model.refreshTrashIfNeeded(now: start.addingTimeInterval(25 * 60 * 60))

    let purgeCount = counter.value
    XCTAssertEqual(purgeCount, 2)
  }

  func testLoadChecksForExpiredTrash() async {
    let counter = CallCounter()
    let model = makeModel(
      storage: makeStorage(
        receipts: [],
        purgeExpiredTrash: { _ in counter.increment() }))

    await model.load()

    let purgeCount = counter.value
    XCTAssertEqual(purgeCount, 1)
  }

  func testOpenedReceiptIsRecentlyOpened() async {
    let receipts = makeReceipts(4)
    let model = makeModel(storage: makeStorage(receipts: receipts))
    await model.load()

    model.markOpened(receipts[2].id)

    XCTAssertEqual(model.recentlyOpened, [receipts[2]])
  }

  func testRecentlyOpenedListsNewestFirst() async {
    let receipts = makeReceipts(4)
    let model = makeModel(storage: makeStorage(receipts: receipts))
    await model.load()

    model.markOpened(receipts[0].id)
    model.markOpened(receipts[1].id)

    XCTAssertEqual(model.recentlyOpened, [receipts[1], receipts[0]])
  }

  func testReopeningAReceiptMovesItToTheFront() async {
    let receipts = makeReceipts(4)
    let model = makeModel(storage: makeStorage(receipts: receipts))
    await model.load()

    model.markOpened(receipts[0].id)
    model.markOpened(receipts[1].id)
    model.markOpened(receipts[0].id)

    XCTAssertEqual(model.recentlyOpened, [receipts[0], receipts[1]])
  }

  func testRecentlyOpenedKeepsThree() async {
    let receipts = makeReceipts(5)
    let model = makeModel(storage: makeStorage(receipts: receipts))
    await model.load()

    for receipt in receipts { model.markOpened(receipt.id) }

    XCTAssertEqual(model.recentlyOpened, [receipts[4], receipts[3], receipts[2]])
  }

  func testRecentlyOpenedIsEmptyWhenItWouldBeTheWholeLibrary() async {
    let receipts = makeReceipts(2)
    let model = makeModel(storage: makeStorage(receipts: receipts))
    await model.load()

    for receipt in receipts { model.markOpened(receipt.id) }

    XCTAssertTrue(model.recentlyOpened.isEmpty)
  }

  func testRecentlyOpenedSkipsUnavailableReceipts() async {
    let receipts = makeReceipts(3) + [ReceiptSummary.fixture(isUnavailable: true)]
    let model = makeModel(storage: makeStorage(receipts: receipts))
    await model.load()

    model.markOpened(receipts[3].id)
    model.markOpened(receipts[0].id)

    XCTAssertEqual(model.recentlyOpened, [receipts[0]])
  }

  func testRecentlyOpenedIsEmptyWhenItWouldBeEveryAvailableReceipt() async {
    let receipts = makeReceipts(2) + [ReceiptSummary.fixture(isUnavailable: true)]
    let model = makeModel(storage: makeStorage(receipts: receipts))
    await model.load()

    model.markOpened(receipts[0].id)
    model.markOpened(receipts[1].id)

    XCTAssertTrue(model.recentlyOpened.isEmpty)
  }

  func testDeletedReceiptLeavesRecentlyOpened() async {
    let receipts = makeReceipts(4)
    let recents = RecentReceiptStore.memory()
    let model = makeModel(storage: makeStorage(receipts: receipts), recents: recents)
    await model.load()
    model.markOpened(receipts[0].id)

    await model.delete(receipts[0])

    XCTAssertTrue(model.recentlyOpened.isEmpty)
    XCTAssertTrue(recents.load().isEmpty)
  }

  func testFailedDeleteKeepsReceiptRecentlyOpened() async {
    let receipts = makeReceipts(4)
    let model = makeModel(
      storage: makeStorage(receipts: receipts, deleteError: .deleteFailed))
    await model.load()
    model.markOpened(receipts[0].id)

    await model.delete(receipts[0])

    XCTAssertEqual(model.recentlyOpened, [receipts[0]])
  }

  func testRecentlyOpenedIsSavedAndLoaded() async {
    let receipts = makeReceipts(4)
    let recents = RecentReceiptStore.memory()
    makeModel(storage: makeStorage(receipts: receipts), recents: recents)
      .markOpened(receipts[1].id)

    let model = makeModel(storage: makeStorage(receipts: receipts), recents: recents)
    await model.load()

    XCTAssertEqual(model.recentlyOpened, [receipts[1]])
  }

  private func makeModel(
    storage: ReceiptStorageClient,
    recents: RecentReceiptStore = .memory()
  ) -> ReceiptLibraryModel {
    ReceiptLibraryModel(storage: storage, recents: recents)
  }

  private func makeReceipts(_ count: Int) -> [ReceiptSummary] {
    (0..<count).map { _ in ReceiptSummary.fixture() }
  }

  private func makeDeletedSummary() -> DeletedReceiptSummary {
    DeletedReceiptSummary(receipt: ReceiptSummary.fixture(), deletedAt: Date())
  }

  private func makeStorage(
    receipts: [ReceiptSummary],
    deletedReceipts: [DeletedReceiptSummary] = [],
    deleteError: TestError? = nil,
    restoreError: TestError? = nil,
    purgeExpiredTrash: @escaping @Sendable (Date) async throws -> Void = { _ in }
  ) -> ReceiptStorageClient {
    var storage = ReceiptStorageClient.unimplemented
    storage.list = { receipts }
    storage.delete = { _ in
      if let deleteError { throw deleteError }
    }
    storage.listDeleted = { deletedReceipts }
    storage.restore = { _ in
      if let restoreError { throw restoreError }
    }
    storage.purgeExpiredTrash = purgeExpiredTrash
    return storage
  }
}
