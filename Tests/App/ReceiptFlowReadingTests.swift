import XCTest

@testable import open_receipt

@MainActor
final class ReceiptFlowReadingTests: XCTestCase, ReceiptFlowTesting {
  func testRecognitionInputStartsRecognizing() {
    let storage = storage(for: ReceiptScan(pages: []))
    let recognition = ReceiptRecognitionCenter.testing(storage: storage).recognize(
      ReceiptScan(pages: []))
    let model = ReceiptFlowModel(input: .recognition(recognition))

    guard case .recognizing(let active) = model.phase else {
      return XCTFail("Expected recognizing phase")
    }
    XCTAssertTrue(active === recognition)
  }

  func testSuccessfulRecognitionCreatesReviewDraft() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = ReceiptRecognitionCenter.testing(storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.performWork(using: center, storage: storage)

    XCTAssertEqual(model.reviewingDraft?.merchantName, "Juniper Market")
  }

  func testFailedRecognitionCanRetry() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let client = ReceiptParsingClient { _ in
      throw TestError.failed
    }
    let center = ReceiptRecognitionCenter.testing(parsingClient: client, storage: storage)
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
    let client = ReceiptParsingClient { _ in
      throw ReceiptParserError.refused
    }
    let center = ReceiptRecognitionCenter.testing(parsingClient: client, storage: storage)
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
    let center = ReceiptRecognitionCenter.testing(
      storage: storage, access: lockedAccess(used: ReadingAccess.freeReadLimit))
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
    let access = lockedAccess(used: ReadingAccess.freeReadLimit)
    let center = ReceiptRecognitionCenter.testing(storage: storage, access: access)
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
    let parsingClient = ReceiptParsingClient { _ in
      parses.increment()
      return ParsedReceipt(merchantName: "Saved")
    }
    let center = ReceiptRecognitionCenter.testing(parsingClient: parsingClient, storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.performWork(using: center, storage: storage)
    guard case .failed = model.phase else {
      return XCTFail("Expected failed phase")
    }
    model.retry(using: center)
    await model.performWork(using: center, storage: storage)

    XCTAssertNotNil(model.reviewingDraft)
    let parseCount = parses.value
    XCTAssertEqual(parseCount, 1)
  }

  func testNewScanStartsRecognizingWhenModelIsAvailable() {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)

    let model = ReceiptFlowModel(
      input: .scan(scan, recognitions: ReceiptRecognitionCenter.testing(storage: storage)))

    guard case .recognizing = model.phase else {
      return XCTFail("Expected recognizing phase")
    }
  }

  func testNewScanIsStoredWhenModelIsUnavailable() {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: unavailableClient(), storage: storage)

    let model = ReceiptFlowModel(input: .scan(scan, recognitions: center))

    guard case .storing = model.phase else {
      return XCTFail("Expected storing phase")
    }
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
