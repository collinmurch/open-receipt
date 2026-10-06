import Synchronization
import XCTest

@testable import open_receipt

@MainActor
final class ReceiptFlowStoredReceiptTests: XCTestCase, ReceiptFlowTesting {
  func testStoredSuccessfulReceiptLoadsReview() async {
    let scan = ReceiptScan(pages: [])
    let draft = ReceiptDraft(receipt: ParsedReceipt(merchantName: "Saved"), id: scan.id)
    let completed = ReceiptDocument.pending(for: scan).updating(from: draft)
    let storage = storage(document: completed)
    let model = ReceiptFlowModel(input: .storedReceipt(scan.id))

    await model.performWork(using: center(storage: storage), storage: storage)

    XCTAssertEqual(model.reviewingDraft?.merchantName, "Saved")
    XCTAssertEqual(model.backgroundStyle, completed.presentation.backgroundStyle)
  }

  func testLoadFailureCanRetrySameReceipt() async {
    let id = UUID()
    let model = ReceiptFlowModel(input: .storedReceipt(id))
    var storage = ReceiptStorageClient.unimplemented
    storage.list = { [] }
    storage.pageURLs = { _ in [] }
    storage.save = { _ in }
    storage.delete = { _ in }
    let center = center(storage: storage)

    await model.performWork(using: center, storage: storage)
    model.retry(using: center)

    guard case .loading(let retryID) = model.phase else {
      return XCTFail("Expected loading phase")
    }
    XCTAssertEqual(retryID, id)
  }

  func testPreloadedReceiptOpensInReview() {
    let scan = ReceiptScan(pages: [])
    let draft = ReceiptDraft(receipt: ParsedReceipt(merchantName: "Saved"), id: scan.id)
    let completed = ReceiptDocument.pending(for: scan).updating(from: draft)

    let model = ReceiptFlowModel(input: .storedReceipt(scan.id, document: completed))

    XCTAssertEqual(model.reviewingDraft?.merchantName, "Saved")
    XCTAssertNil(model.workID)
  }

  func testPreloadedUnreadReceiptOpensWaitingToBeRead() {
    let scan = ReceiptScan(pages: [])

    let model = ReceiptFlowModel(
      input: .storedReceipt(scan.id, document: .pending(for: scan)))

    XCTAssertEqual(model.failure?.title, "Receipt Not Read")
  }

  func testPreloadedDocumentForAnotherReceiptIsIgnored() {
    let scan = ReceiptScan(pages: [])
    let other = ReceiptDocument.pending(for: ReceiptScan(pages: []))

    let model = ReceiptFlowModel(input: .storedReceipt(scan.id, document: other))

    guard case .loading(let id) = model.phase else {
      return XCTFail("Expected loading phase")
    }
    XCTAssertEqual(id, scan.id)
  }

  func testStoredPendingReceiptWaitsToBeRead() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let model = ReceiptFlowModel(input: .storedReceipt(scan.id))

    await model.performWork(using: center(storage: storage), storage: storage)

    guard case .failed(let failure) = model.phase else {
      return XCTFail("Expected an unread receipt")
    }
    XCTAssertEqual(failure.title, "Receipt Not Read")
    XCTAssertTrue(failure.allowsManualEntry)
    guard case .read(let id) = failure.retry else {
      return XCTFail("Expected a read action")
    }
    XCTAssertEqual(id, scan.id)
  }

  func testStoredPendingReceiptDoesNotCallModel() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let parses = CallCounter()
    let parsingClient = ReceiptParsingClient(usesSampleData: false) { _ in
      await parses.increment()
      return ParsedReceipt(merchantName: "Saved")
    }
    let model = ReceiptFlowModel(input: .storedReceipt(scan.id))

    await model.performWork(
      using: center(parsingClient: parsingClient, storage: storage), storage: storage)

    let parseCount = await parses.value
    XCTAssertEqual(parseCount, 0)
  }

  func testStoredPendingReceiptUsesFreeRead() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let model = ReceiptFlowModel(input: .storedReceipt(scan.id))

    await model.performWork(using: center(storage: storage), storage: storage)

    XCTAssertEqual(model.failure?.usesFreeRead, true)
  }

  func testStoredDeferredReceiptUsesNoNewFreeRead() async {
    let scan = ReceiptScan(pages: [])
    var document = ReceiptDocument.pending(for: scan)
    document.recognition.status = .failed
    document.recognition.deferredUntil = Date().addingTimeInterval(3600)
    let storage = storage(document: document)
    let model = ReceiptFlowModel(input: .storedReceipt(scan.id))

    await model.performWork(using: center(storage: storage), storage: storage)

    XCTAssertEqual(model.failure?.usesFreeRead, false)
  }

  func testStoredDeferredReceiptWaitsForReadingLimit() async {
    let scan = ReceiptScan(pages: [])
    var document = ReceiptDocument.pending(for: scan)
    document.recognition.status = .failed
    document.recognition.deferredUntil = Date().addingTimeInterval(3600)
    let storage = storage(document: document)
    let model = ReceiptFlowModel(input: .storedReceipt(scan.id))

    await model.performWork(using: center(storage: storage), storage: storage)

    guard case .failed(let failure) = model.phase else {
      return XCTFail("Expected an unread receipt")
    }
    XCTAssertEqual(failure.title, "Waiting to Read")
  }

  func testReadingStoredReceiptStartsRecognizing() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(storage: storage)
    let model = ReceiptFlowModel(input: .storedReceipt(scan.id))
    await model.performWork(using: center, storage: storage)

    model.retry(using: center)
    await model.performWork(using: center, storage: storage)

    guard case .recognizing(let recognition) = model.phase else {
      return XCTFail("Expected recognizing phase")
    }
    XCTAssertEqual(recognition.id, scan.id)
  }

  func testReadingStoredReceiptPrewarmsModel() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let prewarms = FlowPrewarmCounter()
    let parsingClient = ReceiptParsingClient(
      usesSampleData: false,
      stream: { _, _ in ParsedReceipt(merchantName: "Saved") },
      prewarm: { prewarms.increment() })
    let center = center(parsingClient: parsingClient, storage: storage)
    let model = ReceiptFlowModel(input: .storedReceipt(scan.id))
    await model.performWork(using: center, storage: storage)

    model.retry(using: center)
    await model.performWork(using: center, storage: storage)

    XCTAssertEqual(prewarms.count, 1)
  }

  func testOpeningReceiptBeingReadJoinsActiveRecognition() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(storage: storage)
    let recognition = center.recognize(scan)
    let model = ReceiptFlowModel(input: .storedReceipt(scan.id))

    await model.performWork(using: center, storage: storage)

    guard case .recognizing(let active) = model.phase else {
      return XCTFail("Expected recognizing phase")
    }
    XCTAssertTrue(active === recognition)
  }

  func testStoredUnreadScanWaitsToBeRead() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(parsingClient: unavailableClient(), storage: storage)
    let model = ReceiptFlowModel(input: .scan(scan, recognitions: center))

    await model.performWork(using: center, storage: storage)

    guard case .failed(let failure) = model.phase else {
      return XCTFail("Expected an unread receipt")
    }
    XCTAssertEqual(failure.title, "Receipt Not Read")
    XCTAssertFalse(failure.isError)
    XCTAssertTrue(failure.allowsManualEntry)
  }

  func testStoredUnreadScanDoesNotCallModel() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let parses = CallCounter()
    let center = center(parsingClient: unavailableClient(parses: parses), storage: storage)
    let model = ReceiptFlowModel(input: .scan(scan, recognitions: center))

    await model.performWork(using: center, storage: storage)

    let parseCount = await parses.value
    XCTAssertEqual(parseCount, 0)
  }

  func testStoringFailureCanRetry() async {
    let scan = ReceiptScan(pages: [])
    var storage = storage(for: scan)
    storage.create = { _, _ in throw TestError.failed }
    let center = center(parsingClient: unavailableClient(), storage: storage)
    let model = ReceiptFlowModel(input: .scan(scan, recognitions: center))
    await model.performWork(using: center, storage: storage)

    model.retry(using: center)

    guard case .storing = model.phase else {
      return XCTFail("Expected the scan to be stored again")
    }
  }

  func testFlowInputsWithSameReceiptAreEqual() {
    let id = UUID()

    XCTAssertEqual(
      ReceiptFlowInput.storedReceipt(id),
      ReceiptFlowInput.storedReceipt(id, backgroundStyle: .mint))
  }
}

private final class FlowPrewarmCounter: Sendable {
  private let value = Mutex(0)

  var count: Int { value.withLock { $0 } }

  func increment() {
    value.withLock { $0 += 1 }
  }
}
