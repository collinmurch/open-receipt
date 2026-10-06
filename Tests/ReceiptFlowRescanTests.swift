import XCTest

@testable import open_receipt

@MainActor
final class ReceiptFlowRescanTests: XCTestCase, ReceiptFlowTesting {
  func testRescanWithoutPageChangesStaysInReview() async {
    let document = recognizedDocument(pageCount: 1, recognizedCount: 1)
    let storage = storage(document: document)
    let model = ReceiptFlowModel(input: .storedReceipt(document.id))
    await model.performWork(using: center(storage: storage), storage: storage)

    model.rescan()

    XCTAssertNotNil(model.reviewingDraft)
  }

  func testRescanAfterPageChangesStartsRescanning() async {
    let document = recognizedDocument(pageCount: 2, recognizedCount: 1)
    let storage = storage(document: document)
    let model = ReceiptFlowModel(input: .storedReceipt(document.id))
    await model.performWork(using: center(storage: storage), storage: storage)

    model.rescan()

    guard case .rescanning = model.phase else {
      return XCTFail("Expected rescanning phase")
    }
    XCTAssertTrue(model.isRecognizing)
  }

  func testRescanReadsReceiptAgain() async throws {
    let document = recognizedDocument(pageCount: 2, recognizedCount: 1)
    let storage = storage(document: document)
    let center = center(parsingClient: rescanningClient(), storage: storage)
    let model = ReceiptFlowModel(input: .storedReceipt(document.id))
    await model.performWork(using: center, storage: storage)

    model.rescan()
    await model.performWork(using: center, storage: storage)
    await model.performWork(using: center, storage: storage)

    XCTAssertEqual(try XCTUnwrap(model.reviewingDraft).merchantName, "Rescanned")
  }

  func testRescanRecordsRecognizedPages() async {
    let document = recognizedDocument(pageCount: 2, recognizedCount: 1)
    let storage = storage(document: document)
    let center = center(parsingClient: rescanningClient(), storage: storage)
    let model = ReceiptFlowModel(input: .storedReceipt(document.id))
    await model.performWork(using: center, storage: storage)

    model.rescan()
    await model.performWork(using: center, storage: storage)
    await model.performWork(using: center, storage: storage)

    XCTAssertNotNil(model.reviewingDraft)
    XCTAssertFalse(model.pages.needsRescan)
  }

  func testFailedRescanDoesNotMarkReceiptFailed() async {
    let document = recognizedDocument(pageCount: 2, recognizedCount: 1)
    let recorder = SaveRecorder()
    let storage = storage(document: document, recorder: recorder)
    let failingClient = ReceiptParsingClient(usesSampleData: false) { _ in
      throw TestError.failed
    }
    let center = center(parsingClient: failingClient, storage: storage)
    let model = ReceiptFlowModel(input: .storedReceipt(document.id))
    await model.performWork(using: center, storage: storage)

    model.rescan()
    await model.performWork(using: center, storage: storage)
    await model.performWork(using: center, storage: storage)

    guard case .failed = model.phase else {
      return XCTFail("Expected failed phase")
    }
    let saved = await recorder.documents
    XCTAssertTrue(saved.allSatisfy { $0.recognition.status == .succeeded })
  }

  func testFailedRescanReturnsToReceipt() async {
    let document = recognizedDocument(pageCount: 2, recognizedCount: 1)
    let storage = storage(document: document)
    let center = center(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .storedReceipt(document.id))
    await model.performWork(using: center, storage: storage)

    model.rescan()
    await model.performWork(using: center, storage: storage)
    await model.performWork(using: center, storage: storage)

    guard case .failed(let failure) = model.phase else {
      return XCTFail("Expected failed phase")
    }
    XCTAssertEqual(failure.title, "Couldn’t Read Receipt Again")
    XCTAssertEqual(failure.manualEntryTitle, "Back to Receipt")
  }

  func testAddingPagesUpdatesReviewedPages() async throws {
    let document = recognizedDocument(pageCount: 1, recognizedCount: 1)
    var updated = document
    updated.scan.pages.append(
      ReceiptDocument.Page(id: UUID(), file: "pages/added.heic", mediaType: "image/heic"))
    let storage = storage(document: document, addPages: { [updated] _, _ in updated })
    let model = ReceiptFlowModel(input: .storedReceipt(document.id))
    await model.performWork(using: center(storage: storage), storage: storage)

    try await model.addPages([], storage: storage)

    XCTAssertEqual(model.pages.pages, updated.scan.pages)
    XCTAssertTrue(model.pages.needsRescan)
  }
}
