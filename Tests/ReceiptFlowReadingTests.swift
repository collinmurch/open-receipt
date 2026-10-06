import XCTest

@testable import open_receipt

@MainActor
final class ReceiptFlowReadingTests: XCTestCase, ReceiptFlowTesting {
  func testRecognitionInputStartsRecognizing() {
    let storage = storage(for: ReceiptScan(pages: []))
    let recognition = center(storage: storage).recognize(ReceiptScan(pages: []))
    let model = ReceiptFlowModel(input: .recognition(recognition))

    guard case .recognizing(let active) = model.phase else {
      return XCTFail("Expected recognizing phase")
    }
    XCTAssertTrue(active === recognition)
    XCTAssertTrue(model.isRecognizing)
  }

  func testSuccessfulRecognitionCreatesReviewDraft() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.performWork(using: center, storage: storage)

    XCTAssertEqual(model.reviewingDraft?.merchantName, "Juniper Market")
    XCTAssertFalse(model.isRecognizing)
  }

  func testFailedRecognitionCanRetry() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      throw TestError.failed
    }
    let center = center(parsingClient: client, storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))
    await model.performWork(using: center, storage: storage)

    guard case .failed(let failure) = model.phase else {
      return XCTFail("Expected failed phase")
    }
    XCTAssertNotNil(failure.retry)

    model.retry(using: center)

    guard case .recognizing = model.phase else {
      return XCTFail("Expected the receipt to be read again")
    }
  }

  func testRefusedRecognitionCannotRetry() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      throw ReceiptParserError.refused
    }
    let center = center(parsingClient: client, storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.performWork(using: center, storage: storage)

    guard case .failed(let failure) = model.phase else {
      return XCTFail("Expected failed phase")
    }
    XCTAssertNil(failure.retry)
  }

  func testReadWithoutFreeReadsOffersUnlock() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(storage: storage, access: .locked(used: ReadingAccess.freeReadLimit))
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.performWork(using: center, storage: storage)

    guard case .failed(let failure) = model.phase else {
      return XCTFail("Expected failed phase")
    }
    XCTAssertTrue(failure.usesFreeRead)
    XCTAssertFalse(failure.isError)
    XCTAssertTrue(failure.allowsManualEntry)
  }

  func testReadWithoutFreeReadsCanRetryAfterUnlocking() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let access = ReadingAccess.locked(used: ReadingAccess.freeReadLimit)
    let center = center(storage: storage, access: access)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))
    await model.performWork(using: center, storage: storage)

    _ = try? await access.purchase()
    model.retry(using: center)
    await performRemainingWork(of: model, using: center, storage: storage)

    XCTAssertNotNil(model.reviewingDraft)
  }

  func testCompletedSaveFailureRetriesWithoutParsingAgain() async {
    let scan = ReceiptScan(pages: [])
    let pending = ReceiptDocument.pending(for: scan)
    let parses = CallCounter()
    let saves = FlowFailingSaveSequence(failures: 1)
    var storage = storage(document: pending)
    storage.save = { document in
      if document.recognition.status == .succeeded {
        try await saves.save(document)
      }
    }
    let parsingClient = ReceiptParsingClient(usesSampleData: false) { _ in
      await parses.increment()
      return ParsedReceipt(merchantName: "Saved")
    }
    let center = center(parsingClient: parsingClient, storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.performWork(using: center, storage: storage)
    guard case .failed = model.phase else {
      return XCTFail("Expected failed phase")
    }
    model.retry(using: center)
    await model.performWork(using: center, storage: storage)

    XCTAssertNotNil(model.reviewingDraft)
    let parseCount = await parses.value
    XCTAssertEqual(parseCount, 1)
  }

  func testNewScanStartsRecognizingWhenModelIsAvailable() {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)

    let model = ReceiptFlowModel(input: .scan(scan, recognitions: center(storage: storage)))

    guard case .recognizing = model.phase else {
      return XCTFail("Expected recognizing phase")
    }
  }

  func testNewScanIsStoredWhenModelIsUnavailable() {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(parsingClient: unavailableClient(), storage: storage)

    let model = ReceiptFlowModel(input: .scan(scan, recognitions: center))

    guard case .storing = model.phase else {
      return XCTFail("Expected storing phase")
    }
    XCTAssertFalse(model.isRecognizing)
    XCTAssertNil(center.recognition(for: scan.id))
  }
}

private actor FlowFailingSaveSequence {
  private var failures: Int

  init(failures: Int) {
    self.failures = failures
  }

  func save(_ document: ReceiptDocument) throws {
    if failures > 0 {
      failures -= 1
      throw TestError.failed
    }
  }
}
