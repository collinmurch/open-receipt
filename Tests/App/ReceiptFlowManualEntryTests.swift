import XCTest

@testable import open_receipt

@MainActor
final class ReceiptFlowManualEntryTests: XCTestCase, ReceiptFlowTesting {
  func testFailedRecognitionAllowsManualEntry() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = ReceiptRecognitionCenter.testing(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.performWork(using: center, storage: storage)

    guard case .failed(let failure) = model.phase else {
      return XCTFail("Expected failed phase")
    }
    XCTAssertTrue(failure.allowsManualEntry)
  }

  func testRefusedRecognitionAllowsManualEntry() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let client = ReceiptParsingClient { _ in
      throw ReceiptParserError.refused
    }
    let center = ReceiptRecognitionCenter.testing(parsingClient: client, storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.performWork(using: center, storage: storage)

    guard case .failed(let failure) = model.phase else {
      return XCTFail("Expected failed phase")
    }
    XCTAssertTrue(failure.allowsManualEntry)
  }

  func testLoadFailureDoesNotAllowManualEntry() async {
    let id = UUID()
    let model = ReceiptFlowModel(input: .storedReceipt(id))
    let storage = storage(document: .pending(for: ReceiptScan(pages: [])))
    var failingStorage = storage
    failingStorage.load = { _ in throw TestError.failed }

    await model.performWork(
      using: ReceiptRecognitionCenter.testing(storage: failingStorage), storage: failingStorage)

    guard case .failed(let failure) = model.phase else {
      return XCTFail("Expected failed phase")
    }
    XCTAssertFalse(failure.allowsManualEntry)
  }

  func testFailedReadOffersManualEntry() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = ReceiptRecognitionCenter.testing(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.performWork(using: center, storage: storage)

    XCTAssertEqual(model.failure?.manualEntryTitle, "Enter Manually")
  }

  func testEnterManuallyOpensBlankReview() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = ReceiptRecognitionCenter.testing(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage)

    XCTAssertEqual(model.reviewingDraft?.merchantName, "")
    XCTAssertEqual(model.reviewingDraft?.items.isEmpty, true)
  }

  func testEnterManuallySavesSucceededReceipt() async {
    let scan = ReceiptScan(pages: [])
    let recorder = Recorder<ReceiptDocument>()
    let storage = storage(document: .pending(for: scan), recorder: recorder)
    let center = ReceiptRecognitionCenter.testing(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage)

    let saved = await recorder.values
    XCTAssertEqual(saved.last?.recognition.status, .succeeded)
    XCTAssertNotNil(saved.last?.receipt)
  }

  func testEnterManuallyAppliesOwner() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = ReceiptRecognitionCenter.testing(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage) {
      ReceiptOwner(contactIdentifier: "me", displayName: "Alex")
    }

    XCTAssertEqual(model.reviewingDraft?.currentUser?.displayName, "Alex")
  }

  func testEnterManuallyKeepsScanPagesForRescan() async {
    let scan = ReceiptScan(pages: [])
    var pending = ReceiptDocument.pending(for: scan)
    pending.scan.pages = [
      ReceiptDocument.Page(id: UUID(), file: "pages/page.heic", mediaType: "image/heic")
    ]
    let storage = storage(document: pending)
    let center = ReceiptRecognitionCenter.testing(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage)

    XCTAssertEqual(model.pages, pending.scan.pages)
    XCTAssertTrue(model.needsRescan)
  }

  func testEnterManuallyAfterFailedRescanKeepsStoredValues() async {
    let document = recognizedDocument(pageCount: 2, recognizedCount: 1)
    let recorder = Recorder<ReceiptDocument>()
    let storage = storage(document: document, recorder: recorder)
    let center = ReceiptRecognitionCenter.testing(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .storedReceipt(document.id))
    await model.performWork(using: center, storage: storage)
    model.rescan()
    await model.performWork(using: center, storage: storage)
    await model.performWork(using: center, storage: storage)
    let savesBeforeManualEntry = await recorder.values.count

    await model.enterManually(storage: storage)

    XCTAssertEqual(model.reviewingDraft?.merchantName, "Saved")
    let savesAfterManualEntry = await recorder.values.count
    XCTAssertEqual(savesAfterManualEntry, savesBeforeManualEntry)
  }

  func testEnterManuallyLoadFailureStaysFailed() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = ReceiptRecognitionCenter.testing(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))
    await model.performWork(using: center, storage: storage)
    var failingStorage = storage
    failingStorage.load = { _ in throw TestError.failed }

    await model.enterManually(storage: failingStorage)

    guard case .failed(let failure) = model.phase else {
      return XCTFail("Expected failed phase")
    }
    XCTAssertTrue(failure.allowsManualEntry)
  }

  func testStoredUnreadScanCanBeEnteredManually() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: unavailableClient(), storage: storage)
    let model = ReceiptFlowModel(input: .scan(scan, recognitions: center))
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage)

    XCTAssertNotNil(model.reviewingDraft)
  }

  func testStoppingReadWaitingForConnectionOpensBlankReview() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: offlineClient(), storage: storage, connectivity: .offline)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.stopReadingAndEnterManually(using: center, storage: storage)

    XCTAssertNotNil(model.reviewingDraft)
    XCTAssertNil(center.recognition(for: scan.id))
  }

  func testStoppingRescanWaitingForConnectionKeepsStoredValues() async {
    let document = recognizedDocument(pageCount: 2, recognizedCount: 1)
    let storage = storage(document: document)
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: offlineClient(), storage: storage, connectivity: .offline)
    let model = ReceiptFlowModel(input: .storedReceipt(document.id))
    await model.performWork(using: center, storage: storage)
    model.rescan()
    await model.performWork(using: center, storage: storage)

    await model.stopReadingAndEnterManually(using: center, storage: storage)

    XCTAssertEqual(model.reviewingDraft?.merchantName, "Saved")
  }

  func testStoppedReadDoesNotShowFailure() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: offlineClient(), storage: storage, connectivity: .offline)
    let recognition = center.recognize(scan)
    let model = ReceiptFlowModel(input: .recognition(recognition))
    let work = Task { await model.performWork(using: center, storage: storage) }

    await center.cancel(recognition)
    await work.value

    guard case .recognizing = model.phase else {
      return XCTFail("Expected the stopped read to leave the phase alone")
    }
  }

  func testReadReceiptDoesNotStartInEditing() async {
    let (model, _) = await reviewingModel(merchantName: "Cafe")

    XCTAssertFalse(model.startsInEditing)
  }

  func testEnteringUnreadReceiptManuallyStartsInEditing() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = ReceiptRecognitionCenter.testing(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage)

    XCTAssertTrue(model.startsInEditing)
  }

  func testStoppingReadToEnterManuallyStartsInEditing() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: offlineClient(), storage: storage, connectivity: .offline)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.stopReadingAndEnterManually(using: center, storage: storage)

    XCTAssertTrue(model.startsInEditing)
  }

  func testReturningFromFailedRescanDoesNotStartInEditing() async {
    let document = recognizedDocument(pageCount: 2, recognizedCount: 1)
    let storage = storage(document: document)
    let center = ReceiptRecognitionCenter.testing(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .storedReceipt(document.id))
    await model.performWork(using: center, storage: storage)
    model.rescan()
    await model.performWork(using: center, storage: storage)
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage)

    XCTAssertFalse(model.startsInEditing)
  }
}
