import XCTest

@testable import open_receipt

@MainActor
final class ReceiptLibraryModelTests: XCTestCase {
  func testSuccessfulDeleteRemovesReceipt() async {
    let receipt = makeSummary()
    let model = ReceiptLibraryModel(storage: makeStorage(receipts: [receipt]))
    await model.load()

    await model.delete(receipt)

    XCTAssertTrue(model.receipts.isEmpty)
    XCTAssertNil(model.errorDescription)
  }

  func testFailedDeleteRestoresReceipt() async {
    let receipt = makeSummary()
    let model = ReceiptLibraryModel(
      storage: makeStorage(receipts: [receipt], deleteError: .deleteFailed))
    await model.load()

    await model.delete(receipt)

    XCTAssertEqual(model.receipts, [receipt])
    XCTAssertNotNil(model.errorDescription)
  }

  func testDeletingUnlistedReceiptDeletesStoredReceipt() async {
    let model = ReceiptLibraryModel(storage: makeStorage(receipts: []))
    await model.load()

    await model.delete(makeSummary())

    XCTAssertTrue(model.receipts.isEmpty)
    XCTAssertNil(model.errorDescription)
  }

  func testFailedDeleteOfUnlistedReceiptShowsError() async {
    let model = ReceiptLibraryModel(
      storage: makeStorage(receipts: [], deleteError: .deleteFailed))
    await model.load()

    await model.delete(makeSummary())

    XCTAssertNotNil(model.errorDescription)
  }

  func testLoadGroupsReceiptsIntoSections() async {
    let receipt = makeSummary()
    let model = ReceiptLibraryModel(storage: makeStorage(receipts: [receipt]))

    await model.load()

    XCTAssertEqual(model.sections.map(\.id), ["2026-08-01"])
    XCTAssertEqual(model.sections.first?.receipts, [receipt])
  }

  func testDeleteRemovesReceiptFromSections() async {
    let receipt = makeSummary()
    let model = ReceiptLibraryModel(storage: makeStorage(receipts: [receipt]))
    await model.load()

    await model.delete(receipt)

    XCTAssertTrue(model.sections.isEmpty)
  }

  func testFailedDeleteRestoresReceiptToSections() async {
    let receipt = makeSummary()
    let model = ReceiptLibraryModel(
      storage: makeStorage(receipts: [receipt], deleteError: .deleteFailed))
    await model.load()

    await model.delete(receipt)

    XCTAssertEqual(model.sections.first?.receipts, [receipt])
  }

  func testLoadIncludesRecentlyDeletedReceipts() async {
    let deletedReceipt = makeDeletedSummary()
    let model = ReceiptLibraryModel(
      storage: makeStorage(receipts: [], deletedReceipts: [deletedReceipt]))

    await model.load()

    XCTAssertEqual(model.deletedReceipts, [deletedReceipt])
  }

  func testFailedRestoreKeepsRecentlyDeletedReceipt() async {
    let deletedReceipt = makeDeletedSummary()
    let model = ReceiptLibraryModel(
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
    let model = ReceiptLibraryModel(
      storage: makeStorage(receipts: [], deletedReceipts: [deletedReceipt]))
    await model.load()

    await model.emptyTrash()

    XCTAssertTrue(model.deletedReceipts.isEmpty)
    XCTAssertNil(model.errorDescription)
  }

  func testTrashPurgeCheckIsLimitedToOncePerDay() async {
    let counter = CallCounter()
    let start = Date(timeIntervalSince1970: 1_000_000)
    let model = ReceiptLibraryModel(
      storage: makeStorage(
        receipts: [],
        purgeExpiredTrash: { _ in await counter.increment() }))

    await model.refreshTrashIfNeeded(now: start)
    await model.refreshTrashIfNeeded(now: start.addingTimeInterval(60 * 60))
    await model.refreshTrashIfNeeded(now: start.addingTimeInterval(25 * 60 * 60))

    let purgeCount = await counter.value
    XCTAssertEqual(purgeCount, 2)
  }

  func testLoadChecksForExpiredTrash() async {
    let counter = CallCounter()
    let model = ReceiptLibraryModel(
      storage: makeStorage(
        receipts: [],
        purgeExpiredTrash: { _ in await counter.increment() }))

    await model.load()

    let purgeCount = await counter.value
    XCTAssertEqual(purgeCount, 1)
  }

  private func makeSummary() -> ReceiptSummary {
    ReceiptSummary(
      id: UUID(),
      updatedAt: Date(),
      capturedAt: Date(),
      backgroundStyle: .blue,
      recognitionStatus: .succeeded,
      merchantName: "Cafe",
      localDate: "2026-08-20",
      total: 12,
      currency: "USD",
      isUnavailable: false,
      unavailableDescription: nil)
  }

  private func makeDeletedSummary() -> DeletedReceiptSummary {
    DeletedReceiptSummary(receipt: makeSummary(), deletedAt: Date())
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
