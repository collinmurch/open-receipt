#if !SWIFT_PACKAGE
  import XCTest
  import UIKit
  @testable import open_receipt

  final class ReceiptStorageTests: XCTestCase {
    private var rootURL: URL!
    private var storage: ReceiptFileStorage!

    override func setUp() {
      super.setUp()
      rootURL = FileManager.default.temporaryDirectory
        .appending(path: "open-receipt-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
      storage = ReceiptFileStorage(rootURL: rootURL)
    }

    override func tearDown() {
      if let rootURL {
        try? FileManager.default.removeItem(at: rootURL)
      }
      storage = nil
      rootURL = nil
      super.tearDown()
    }

    func testCreateStoresPendingDocument() async throws {
      let scan = try makeScan()

      let document = try await storage.create(scan: scan)

      XCTAssertEqual(document.id, scan.id)
      XCTAssertEqual(document.recognition.status, .pending)
      XCTAssertEqual(document.scan.pages.count, 1)
    }

    func testCreateRejectsEmptyScan() async {
      do {
        _ = try await storage.create(scan: ReceiptScan(pages: []))
        XCTFail("Expected an empty scan error")
      } catch let error as ReceiptStorageError {
        guard case .emptyScan = error else {
          return XCTFail("Expected an empty scan error")
        }
      } catch {
        XCTFail("Expected a receipt storage error")
      }
    }

    func testCreateBlankStoresEditableDocument() async throws {
      let id = UUID()

      let document = try await storage.createBlank(id: id)

      XCTAssertEqual(document.id, id)
      XCTAssertEqual(document.scan.source, .manual)
      XCTAssertTrue(document.scan.pages.isEmpty)
      XCTAssertEqual(document.recognition.status, .succeeded)
      XCTAssertEqual(document.receipt?.merchant.name, "")
      XCTAssertEqual(document.receipt?.currency, "USD")
      XCTAssertEqual(document.split?.participants.map(\.displayName), ["Me"])
    }

    func testCreatedBlankCanBeLoaded() async throws {
      let id = UUID()
      _ = try await storage.createBlank(id: id)

      let document = try await storage.load(id: id)

      XCTAssertEqual(document.id, id)
      XCTAssertEqual(document.scan.source, .manual)
    }

    func testOlderSchemaVersionIsRejected() async throws {
      let created = try await storage.createBlank(id: UUID())
      var legacy = created
      legacy.schemaVersion = ReceiptDocument.currentSchemaVersion - 1
      try writeDirectly(legacy)

      do {
        _ = try await storage.load(id: created.id)
        XCTFail("Expected an unsupported version error")
      } catch let error as ReceiptDocumentError {
        XCTAssertEqual(
          error,
          .unsupportedSchemaVersion(ReceiptDocument.currentSchemaVersion - 1))
      }
    }

    func testOlderSchemaVersionIsListedAsUnavailable() async throws {
      let created = try await storage.createBlank(id: UUID())
      var legacy = created
      legacy.schemaVersion = ReceiptDocument.currentSchemaVersion - 1
      try writeDirectly(legacy)

      let summaries = try await storage.list()

      XCTAssertEqual(summaries.map(\.isUnavailable), [true])
    }

    func testCreateNamesPageFileByPageIdentifier() async throws {
      let document = try await storage.create(scan: makeScan())

      let page = try XCTUnwrap(document.scan.pages.first)

      XCTAssertEqual(page.file, "pages/\(page.id.uuidString.lowercased()).heic")
    }

    func testAddPagesAppendsPages() async throws {
      let created = try await storage.create(scan: makeScan())

      let updated = try await storage.addPages(makeScan().pages, to: created.id)

      XCTAssertEqual(updated.scan.pages.count, 2)
      XCTAssertEqual(updated.scan.pages.first, created.scan.pages.first)
    }

    func testAddedPagesLoadForParsing() async throws {
      let created = try await storage.create(scan: makeScan())
      _ = try await storage.addPages(makeScan().pages, to: created.id)

      let pages = try await storage.loadPages(id: created.id)

      XCTAssertEqual(pages.map(\.pageIndex), [0, 1])
    }

    func testAddPagesRejectsEmptyPages() async throws {
      let created = try await storage.create(scan: makeScan())

      do {
        _ = try await storage.addPages([], to: created.id)
        XCTFail("Expected an empty scan error")
      } catch let error as ReceiptStorageError {
        guard case .emptyScan = error else { return XCTFail("Expected an empty scan error") }
      }
    }

    func testDeletePageRemovesPage() async throws {
      let created = try await storage.create(scan: makeScan())
      let added = try await storage.addPages(makeScan().pages, to: created.id)
      let removedPage = try XCTUnwrap(created.scan.pages.first)

      let updated = try await storage.deletePage(removedPage.id, from: created.id)

      XCTAssertEqual(updated.scan.pages, Array(added.scan.pages.dropFirst()))
    }

    func testDeletePageRemovesPageFile() async throws {
      let created = try await storage.create(scan: makeScan())
      _ = try await storage.addPages(makeScan().pages, to: created.id)
      let removedPage = try XCTUnwrap(created.scan.pages.first)
      let removedURL =
        rootURL
        .appending(path: created.id.uuidString, directoryHint: .isDirectory)
        .appending(path: removedPage.file)

      _ = try await storage.deletePage(removedPage.id, from: created.id)

      XCTAssertFalse(FileManager.default.fileExists(atPath: removedURL.path))
    }

    func testDeleteLastPageIsRejected() async throws {
      let created = try await storage.create(scan: makeScan())
      let page = try XCTUnwrap(created.scan.pages.first)

      do {
        _ = try await storage.deletePage(page.id, from: created.id)
        XCTFail("Expected a last page error")
      } catch let error as ReceiptStorageError {
        guard case .lastPage = error else { return XCTFail("Expected a last page error") }
      }
    }

    func testReorderPagesStoresNewOrder() async throws {
      let created = try await storage.create(scan: makeScan())
      let added = try await storage.addPages(makeScan().pages, to: created.id)
      let reversed = Array(added.scan.pages.map(\.id).reversed())

      _ = try await storage.reorderPages(reversed, in: created.id)

      let loaded = try await storage.load(id: created.id)
      XCTAssertEqual(loaded.scan.pages.map(\.id), reversed)
    }

    func testReorderedPagesLoadInNewOrder() async throws {
      let created = try await storage.create(scan: makeScan())
      let added = try await storage.addPages(makeScan().pages, to: created.id)
      let reversed = Array(added.scan.pages.reversed())

      _ = try await storage.reorderPages(reversed.map(\.id), in: created.id)

      let urls = try await storage.pageURLs(id: created.id)
      XCTAssertEqual(
        urls.map(\.lastPathComponent), reversed.map { URL(filePath: $0.file).lastPathComponent })
    }

    func testReorderPagesRejectsMissingPage() async throws {
      let created = try await storage.create(scan: makeScan())
      let added = try await storage.addPages(makeScan().pages, to: created.id)

      do {
        _ = try await storage.reorderPages(
          [try XCTUnwrap(added.scan.pages.first).id], in: created.id)
        XCTFail("Expected a pages changed error")
      } catch let error as ReceiptStorageError {
        guard case .pagesChanged = error else { return XCTFail("Expected a pages changed error") }
      }
    }

    func testReorderPagesRejectsDuplicatePage() async throws {
      let created = try await storage.create(scan: makeScan())
      let added = try await storage.addPages(makeScan().pages, to: created.id)
      let first = try XCTUnwrap(added.scan.pages.first).id

      do {
        _ = try await storage.reorderPages([first, first], in: created.id)
        XCTFail("Expected a pages changed error")
      } catch let error as ReceiptStorageError {
        guard case .pagesChanged = error else { return XCTFail("Expected a pages changed error") }
      }
    }

    func testSaveKeepsStoredPages() async throws {
      let created = try await storage.create(scan: makeScan())
      let added = try await storage.addPages(makeScan().pages, to: created.id)
      var stale = created
      stale.updatedAt = added.updatedAt.addingTimeInterval(1)

      try await storage.save(stale)

      let loaded = try await storage.load(id: created.id)
      XCTAssertEqual(loaded.scan.pages, added.scan.pages)
    }

    func testCreateStoresHEICPage() async throws {
      let scan = try makeScan()
      let document = try await storage.create(scan: scan)

      let urls = try await storage.pageURLs(id: document.id)

      XCTAssertEqual(urls.map(\.pathExtension), ["heic"])
      XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(urls.first).path))
    }

    func testStoredPageLoadsForParsing() async throws {
      let scan = try makeScan()
      let document = try await storage.create(scan: scan)

      let pages = try await storage.loadPages(id: document.id)

      XCTAssertEqual(pages.count, 1)
      XCTAssertEqual(pages[0].pageIndex, 0)
      XCTAssertEqual(pages[0].orientation, .up)
      XCTAssertEqual(pages[0].image.width, 40)
      XCTAssertEqual(pages[0].image.height, 80)
    }

    func testListReturnsNewestReceiptFirst() async throws {
      let first = try await storage.create(
        scan: makeScan(capturedAt: Date(timeIntervalSince1970: 1)))
      try await Task.sleep(for: .milliseconds(20))
      let second = try await storage.create(
        scan: makeScan(capturedAt: Date(timeIntervalSince1970: 2)))

      let summaries = try await storage.list()

      XCTAssertEqual(summaries.map(\.id), [second.id, first.id])
    }

    func testDeleteMovesReceiptToRecentlyDeleted() async throws {
      let document = try await storage.create(scan: makeScan())

      try await storage.delete(id: document.id)

      let summaries = try await storage.list()
      XCTAssertTrue(summaries.isEmpty)
      let deletedReceipts = try await storage.listDeleted()
      XCTAssertEqual(deletedReceipts.map(\.id), [document.id])
    }

    func testRestoreReturnsReceiptToLibrary() async throws {
      let document = try await storage.create(scan: makeScan())
      try await storage.delete(id: document.id)

      try await storage.restore(id: document.id)

      let receipts = try await storage.list()
      let deletedReceipts = try await storage.listDeleted()
      let pages = try await storage.loadPages(id: document.id)
      XCTAssertEqual(receipts.map(\.id), [document.id])
      XCTAssertTrue(deletedReceipts.isEmpty)
      XCTAssertEqual(pages.count, 1)
    }

    func testPermanentDeleteRemovesDeletedReceipt() async throws {
      let document = try await storage.create(scan: makeScan())
      try await storage.delete(id: document.id)

      try await storage.permanentlyDelete(id: document.id)

      let deletedReceipts = try await storage.listDeleted()
      XCTAssertTrue(deletedReceipts.isEmpty)
    }

    func testEmptyTrashRemovesAllDeletedReceipts() async throws {
      let first = try await storage.create(scan: makeScan())
      let second = try await storage.create(scan: makeScan())
      try await storage.delete(id: first.id)
      try await storage.delete(id: second.id)

      try await storage.emptyTrash()

      let deletedReceipts = try await storage.listDeleted()
      XCTAssertTrue(deletedReceipts.isEmpty)
    }

    func testPurgeKeepsReceiptsYoungerThanThirtyDays() async throws {
      let document = try await storage.create(scan: makeScan())
      try await storage.delete(id: document.id)

      try await storage.purgeExpiredTrash(
        now: Date().addingTimeInterval(29 * 24 * 60 * 60))

      let deletedReceipts = try await storage.listDeleted()
      XCTAssertEqual(deletedReceipts.map(\.id), [document.id])
    }

    func testPurgeRemovesReceiptsOlderThanThirtyDays() async throws {
      let document = try await storage.create(scan: makeScan())
      try await storage.delete(id: document.id)

      try await storage.purgeExpiredTrash(
        now: Date().addingTimeInterval(31 * 24 * 60 * 60))

      let deletedReceipts = try await storage.listDeleted()
      XCTAssertTrue(deletedReceipts.isEmpty)
    }

    func testCorruptDocumentRemainsVisibleForDeletion() async throws {
      let document = try await storage.create(scan: makeScan())
      let documentURL =
        rootURL
        .appending(path: document.id.uuidString, directoryHint: .isDirectory)
        .appending(path: "receipt.json")

      try Data("not-json".utf8).write(to: documentURL)

      let summaries = try await storage.list()

      XCTAssertEqual(summaries.count, 1)
      XCTAssertTrue(summaries[0].isUnavailable)
    }

    func testUnsupportedSchemaVersionIsNotSaved() async throws {
      let created = try await storage.create(scan: makeScan())
      let document = ReceiptDocument(
        schemaVersion: ReceiptDocument.currentSchemaVersion + 1,
        id: created.id,
        createdAt: created.createdAt,
        updatedAt: created.updatedAt,
        presentation: created.presentation,
        scan: created.scan,
        recognition: created.recognition,
        receipt: nil,
        split: nil)

      do {
        try await storage.save(document)
        XCTFail("Expected an unsupported version error")
      } catch let error as ReceiptDocumentError {
        XCTAssertEqual(
          error,
          .unsupportedSchemaVersion(ReceiptDocument.currentSchemaVersion + 1))
      }
    }

    func testOlderSnapshotDoesNotOverwriteNewerSnapshot() async throws {
      let created = try await storage.create(scan: makeScan())
      var newer = created
      newer.updatedAt = created.updatedAt.addingTimeInterval(2)
      newer.recognition.status = .failed
      newer.recognition.failureMessage = "Newer"
      try await storage.save(newer)
      var older = created
      older.updatedAt = created.updatedAt.addingTimeInterval(1)
      older.recognition.status = .failed
      older.recognition.failureMessage = "Older"

      try await storage.save(older)

      let loaded = try await storage.load(id: created.id)
      XCTAssertEqual(loaded.recognition.failureMessage, "Newer")
    }

    func testUnsafePagePathIsRejected() async throws {
      let created = try await storage.create(scan: makeScan())
      let unsafe = ReceiptDocument(
        schemaVersion: created.schemaVersion,
        id: created.id,
        createdAt: created.createdAt,
        updatedAt: created.updatedAt.addingTimeInterval(1),
        presentation: created.presentation,
        scan: .init(
          capturedAt: created.scan.capturedAt,
          source: created.scan.source,
          pages: [.init(id: UUID(), file: "../outside.heic", mediaType: "image/heic")]),
        recognition: created.recognition,
        receipt: created.receipt,
        split: created.split)
      try writeDirectly(unsafe)

      do {
        _ = try await storage.pageURLs(id: unsafe.id)
        XCTFail("Expected an unsafe path error")
      } catch let error as ReceiptDocumentError {
        XCTAssertEqual(error, .invalidPagePath("../outside.heic"))
      }
    }

    func testCreateUsesRequestedBackgroundStyle() async throws {
      let document = try await storage.create(scan: makeScan(), backgroundStyle: .peach)

      XCTAssertEqual(document.presentation.backgroundStyle, .peach)
    }

    func testCreateBlankUsesRequestedBackgroundStyle() async throws {
      let document = try await storage.createBlank(id: UUID(), backgroundStyle: .mint)

      XCTAssertEqual(document.presentation.backgroundStyle, .mint)
    }

    func testListReflectsSavedChanges() async throws {
      let created = try await storage.createBlank(id: UUID())
      _ = try await storage.list()
      var updated = created
      updated.updatedAt = created.updatedAt.addingTimeInterval(1)
      updated.receipt?.merchant.name = "Juniper Market"

      try await storage.save(updated)
      let summaries = try await storage.list()

      XCTAssertEqual(summaries.map(\.merchantName), ["Juniper Market"])
    }

    func testListReloadsReceiptEditedOutsideStorage() async throws {
      let created = try await storage.createBlank(id: UUID())
      _ = try await storage.list()
      var edited = created
      edited.updatedAt = created.updatedAt.addingTimeInterval(1)
      edited.receipt?.merchant.name = "Edited Elsewhere"

      try writeDirectly(edited)
      let summaries = try await storage.list()

      XCTAssertEqual(summaries.map(\.merchantName), ["Edited Elsewhere"])
    }

    func testLoadReturnsReceiptEditedOutsideStorage() async throws {
      let created = try await storage.createBlank(id: UUID())
      _ = try await storage.load(id: created.id)
      var edited = created
      edited.updatedAt = created.updatedAt.addingTimeInterval(1)
      edited.receipt?.merchant.name = "Edited Elsewhere"

      try writeDirectly(edited)
      let loaded = try await storage.load(id: created.id)

      XCTAssertEqual(loaded.receipt?.merchant.name, "Edited Elsewhere")
    }

    func testListOmitsDeletedReceiptAfterIndexing() async throws {
      let created = try await storage.createBlank(id: UUID())
      _ = try await storage.list()

      try await storage.delete(id: created.id)
      let summaries = try await storage.list()

      XCTAssertTrue(summaries.isEmpty)
    }

    func testIndexIsReadByNewStorageInstance() async throws {
      let created = try await storage.createBlank(id: UUID())
      _ = try await storage.list()

      let reopened = ReceiptFileStorage(rootURL: rootURL)
      let summaries = try await reopened.list()

      XCTAssertEqual(summaries.map(\.id), [created.id])
    }

    func testCorruptIndexIsRebuilt() async throws {
      let created = try await storage.createBlank(id: UUID())
      try Data("not json".utf8).write(to: rootURL.appending(path: ".index.json"))

      let reopened = ReceiptFileStorage(rootURL: rootURL)
      let summaries = try await reopened.list()

      XCTAssertEqual(summaries.map(\.id), [created.id])
    }

    func testPersonSnapshotsFollowSavedParticipants() async throws {
      let created = try await storage.createBlank(id: UUID())
      var updated = created
      updated.updatedAt = created.updatedAt.addingTimeInterval(1)
      updated.split?.participants.append(
        .init(
          id: UUID(),
          displayName: "Avery",
          source: .init(type: .manual, identifier: nil)))

      try await storage.save(updated)
      let snapshots = try await storage.listPersonSnapshots()

      XCTAssertEqual(snapshots.map(\.displayName), ["Avery"])
    }

    func testTimestampsKeepFractionalSeconds() async throws {
      let created = try await storage.createBlank(id: UUID())
      let json = try String(
        contentsOf:
          rootURL
          .appending(path: created.id.uuidString, directoryHint: .isDirectory)
          .appending(path: "receipt.json"),
        encoding: .utf8)

      XCTAssertNotNil(
        json.range(
          of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z"#,
          options: .regularExpression))
    }

    private func writeDirectly(_ document: ReceiptDocument) throws {
      let documentURL =
        rootURL
        .appending(path: document.id.uuidString, directoryHint: .isDirectory)
        .appending(path: "receipt.json")
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(document).write(to: documentURL, options: .atomic)
    }

    private func makeScan(capturedAt: Date = Date()) throws -> ReceiptScan {
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: 40, height: 80),
        format: format)
      let image = renderer.image { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 80))
        UIColor.black.setFill()
        context.fill(CGRect(x: 5, y: 5, width: 30, height: 8))
      }
      let cgImage = try XCTUnwrap(image.cgImage)
      let page = ReceiptPage(
        image: cgImage,
        sourceURL: URL(fileURLWithPath: "test"),
        pageIndex: 0)
      return ReceiptScan(
        pages: [page],
        capturedAt: capturedAt,
        source: .documentCamera)
    }
  }
#endif
