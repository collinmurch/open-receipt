import Synchronization
import XCTest

@testable import open_receipt

@MainActor
final class ReceiptFlowModelTests: XCTestCase {
  func testCreateInputStartsInCreatingPhase() {
    let id = UUID()
    let model = ReceiptFlowModel(input: .create(id: id))

    guard case .creating(let creatingID) = model.phase else {
      return XCTFail("Expected creating phase")
    }
    XCTAssertEqual(creatingID, id)
  }

  func testCreateInputCreatesBlankReviewDraft() async throws {
    let id = UUID()
    let document = blankDocument(id: id)
    let storage = storage(document: document)
    let model = ReceiptFlowModel(input: .create(id: id))

    await model.performWork(using: center(storage: storage), storage: storage)

    let draft = try XCTUnwrap(model.reviewingDraft)
    XCTAssertEqual(model.document?.id, id)
    XCTAssertEqual(model.document?.scan.source, .manual)
    XCTAssertEqual(draft.merchantName, "")
    XCTAssertTrue(draft.items.isEmpty)
  }

  func testCreateInputAppliesOwner() async {
    let id = UUID()
    let storage = storage(document: blankDocument(id: id))
    let model = ReceiptFlowModel(input: .create(id: id))

    await model.performWork(using: center(storage: storage), storage: storage) {
      ReceiptOwner(contactIdentifier: "me", displayName: "Alex")
    }

    XCTAssertEqual(
      model.reviewingDraft?.currentUser?.source, .currentUser(contactIdentifier: "me"))
    XCTAssertEqual(model.reviewingDraft?.currentUser?.displayName, "Alex")
  }

  func testCreateInputWithoutOwnerKeepsDefaultName() async {
    let id = UUID()
    let storage = storage(document: blankDocument(id: id))
    let model = ReceiptFlowModel(input: .create(id: id))

    await model.performWork(using: center(storage: storage), storage: storage)

    XCTAssertEqual(model.reviewingDraft?.currentUser?.displayName, "Me")
  }

  func testCreateInputUsesSuppliedBackgroundStyle() {
    let model = ReceiptFlowModel(input: .create(backgroundStyle: .peach))

    XCTAssertEqual(model.backgroundStyle, .peach)
  }

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

  func testFailedRecognitionAllowsManualEntry() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(parsingClient: failingClient(), storage: storage)
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
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      throw ReceiptParserError.refused
    }
    let center = center(parsingClient: client, storage: storage)
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

    await model.performWork(using: center(storage: failingStorage), storage: failingStorage)

    guard case .failed(let failure) = model.phase else {
      return XCTFail("Expected failed phase")
    }
    XCTAssertFalse(failure.allowsManualEntry)
  }

  func testEnterManuallyOpensBlankReview() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage)

    XCTAssertEqual(model.reviewingDraft?.merchantName, "")
    XCTAssertEqual(model.reviewingDraft?.items.isEmpty, true)
  }

  func testEnterManuallySavesSucceededReceipt() async {
    let scan = ReceiptScan(pages: [])
    let recorder = SaveRecorder()
    let storage = storage(document: .pending(for: scan), recorder: recorder)
    let center = center(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage)

    let saved = await recorder.documents
    XCTAssertEqual(saved.last?.recognition.status, .succeeded)
    XCTAssertNotNil(saved.last?.receipt)
  }

  func testEnterManuallyAppliesOwner() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(parsingClient: failingClient(), storage: storage)
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
    let center = center(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage)

    XCTAssertEqual(model.pages.pages, pending.scan.pages)
    XCTAssertTrue(model.pages.needsRescan)
  }

  func testEnterManuallyAfterFailedRescanKeepsStoredValues() async {
    let document = recognizedDocument(pageCount: 2, recognizedCount: 1)
    let recorder = SaveRecorder()
    let storage = storage(document: document, recorder: recorder)
    let center = center(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .storedReceipt(document.id))
    await model.performWork(using: center, storage: storage)
    model.rescan()
    await model.performWork(using: center, storage: storage)
    await model.performWork(using: center, storage: storage)
    let savesBeforeManualEntry = await recorder.documents.count

    await model.enterManually(storage: storage)

    XCTAssertEqual(model.reviewingDraft?.merchantName, "Saved")
    let savesAfterManualEntry = await recorder.documents.count
    XCTAssertEqual(savesAfterManualEntry, savesBeforeManualEntry)
  }

  func testEnterManuallyLoadFailureStaysFailed() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(parsingClient: failingClient(), storage: storage)
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

  func testCompletedSaveFailureRetriesWithoutParsingAgain() async {
    let scan = ReceiptScan(pages: [])
    let pending = ReceiptDocument.pending(for: scan)
    let parser = FlowParseRecorder()
    let saves = FlowFailingSaveSequence(failures: 1)
    var storage = storage(document: pending)
    storage.save = { document in
      if document.recognition.status == .succeeded {
        try await saves.save(document)
      }
    }
    let parsingClient = ReceiptParsingClient(usesSampleData: false) { _ in
      await parser.parse()
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
    let parseCount = await parser.count
    XCTAssertEqual(parseCount, 1)
  }

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
    let parser = FlowParseRecorder()
    let parsingClient = ReceiptParsingClient(usesSampleData: false) { _ in
      await parser.parse()
    }
    let model = ReceiptFlowModel(input: .storedReceipt(scan.id))

    await model.performWork(
      using: center(parsingClient: parsingClient, storage: storage), storage: storage)

    let parseCount = await parser.count
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

  func testAutosaveWritesChangedDraft() async throws {
    let recorder = SaveRecorder()
    let (model, storage) = await reviewingModel(merchantName: "Saved", recorder: recorder)
    let draft = try XCTUnwrap(model.reviewingDraft)

    draft.merchantName = "Updated"
    await model.autosave(storage: storage)

    let saved = await recorder.documents
    XCTAssertEqual(saved.last?.receipt?.merchant.name, "Updated")
  }

  func testFlushWritesWithoutDebounce() async throws {
    let recorder = SaveRecorder()
    let (model, storage) = await reviewingModel(merchantName: "Saved", recorder: recorder)
    let draft = try XCTUnwrap(model.reviewingDraft)
    draft.total = 12

    let didSave = await model.flush(storage: storage)

    XCTAssertTrue(didSave)
    let saved = await recorder.documents
    XCTAssertEqual(saved.last?.receipt?.amounts.total.value, "12.0")
  }

  func testSaveKeepsReviewingSameDraft() async throws {
    let (model, storage) = await reviewingModel(merchantName: "Saved")
    let draft = try XCTUnwrap(model.reviewingDraft)
    draft.merchantName = "Updated"

    _ = await model.flush(storage: storage)

    XCTAssertTrue(model.reviewingDraft === draft)
    XCTAssertEqual(model.document?.receipt?.merchant.name, "Updated")
  }

  func testFlushWithoutChangesDoesNotSave() async {
    let recorder = SaveRecorder()
    let (model, storage) = await reviewingModel(merchantName: "Saved", recorder: recorder)

    _ = await model.flush(storage: storage)

    let saved = await recorder.documents
    XCTAssertTrue(saved.isEmpty)
  }

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

  func testFailedReadOffersManualEntry() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.performWork(using: center, storage: storage)

    XCTAssertEqual(model.failure?.manualEntryTitle, "Enter Manually")
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
    let parser = FlowParseRecorder()
    let center = center(parsingClient: unavailableClient(parser: parser), storage: storage)
    let model = ReceiptFlowModel(input: .scan(scan, recognitions: center))

    await model.performWork(using: center, storage: storage)

    let parseCount = await parser.count
    XCTAssertEqual(parseCount, 0)
  }

  func testStoredUnreadScanCanBeEnteredManually() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(parsingClient: unavailableClient(), storage: storage)
    let model = ReceiptFlowModel(input: .scan(scan, recognitions: center))
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage)

    XCTAssertNotNil(model.reviewingDraft)
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

  func testStoppingReadWaitingForConnectionOpensBlankReview() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(
      parsingClient: offlineClient(), storage: storage, connectivity: .offline)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.stopReadingAndEnterManually(using: center, storage: storage)

    XCTAssertNotNil(model.reviewingDraft)
    XCTAssertNil(center.recognition(for: scan.id))
  }

  func testStoppingRescanWaitingForConnectionKeepsStoredValues() async {
    let document = recognizedDocument(pageCount: 2, recognizedCount: 1)
    let storage = storage(document: document)
    let center = center(
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
    let center = center(
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

  func testCreatedReceiptStartsInEditing() async {
    let id = UUID()
    let storage = storage(document: blankDocument(id: id))
    let model = ReceiptFlowModel(input: .create(id: id))

    await model.performWork(using: center(storage: storage), storage: storage)

    XCTAssertTrue(model.startsInEditing)
  }

  func testReadReceiptDoesNotStartInEditing() async {
    let (model, _) = await reviewingModel(merchantName: "Cafe")

    XCTAssertFalse(model.startsInEditing)
  }

  func testEnteringUnreadReceiptManuallyStartsInEditing() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage)

    XCTAssertTrue(model.startsInEditing)
  }

  func testStoppingReadToEnterManuallyStartsInEditing() async {
    let scan = ReceiptScan(pages: [])
    let storage = storage(for: scan)
    let center = center(
      parsingClient: offlineClient(), storage: storage, connectivity: .offline)
    let model = ReceiptFlowModel(input: .recognition(center.recognize(scan)))

    await model.stopReadingAndEnterManually(using: center, storage: storage)

    XCTAssertTrue(model.startsInEditing)
  }

  func testReturningFromFailedRescanDoesNotStartInEditing() async {
    let document = recognizedDocument(pageCount: 2, recognizedCount: 1)
    let storage = storage(document: document)
    let center = center(parsingClient: failingClient(), storage: storage)
    let model = ReceiptFlowModel(input: .storedReceipt(document.id))
    await model.performWork(using: center, storage: storage)
    model.rescan()
    await model.performWork(using: center, storage: storage)
    await model.performWork(using: center, storage: storage)

    await model.enterManually(storage: storage)

    XCTAssertFalse(model.startsInEditing)
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

  func testFlowInputsWithSameReceiptAreEqual() {
    let id = UUID()

    XCTAssertEqual(
      ReceiptFlowInput.storedReceipt(id),
      ReceiptFlowInput.storedReceipt(id, backgroundStyle: .mint))
  }

  private func reviewingModel(
    merchantName: String,
    recorder: SaveRecorder? = nil
  ) async -> (ReceiptFlowModel, ReceiptStorageClient) {
    let scan = ReceiptScan(pages: [])
    let draft = ReceiptDraft(receipt: ParsedReceipt(merchantName: merchantName), id: scan.id)
    let completed = ReceiptDocument.pending(for: scan).updating(from: draft)
    let storage = storage(document: completed, recorder: recorder)
    let model = ReceiptFlowModel(input: .storedReceipt(scan.id))
    await model.performWork(using: center(storage: storage), storage: storage)
    return (model, storage)
  }

  /// Performs the model's work until it has none left, the way its view does by running it
  /// again whenever the phase changes.
  private func performRemainingWork(
    of model: ReceiptFlowModel,
    using center: ReceiptRecognitionCenter,
    storage: ReceiptStorageClient
  ) async {
    for _ in 0..<10 where model.workID != nil {
      await model.performWork(using: center, storage: storage)
    }
  }

  private func center(
    parsingClient: ReceiptParsingClient = .sample(pacing: .zero),
    storage: ReceiptStorageClient,
    access: ReadingAccess = .unlimited(),
    connectivity: ReceiptConnectivity = .immediate
  ) -> ReceiptRecognitionCenter {
    ReceiptRecognitionCenter(
      parsingClient: parsingClient,
      storage: storage,
      access: access,
      connectivity: connectivity,
      connectionRetryDelay: .zero)
  }

  private func storage(for scan: ReceiptScan) -> ReceiptStorageClient {
    storage(document: .pending(for: scan))
  }

  private func storage(
    document: ReceiptDocument,
    recorder: SaveRecorder? = nil,
    addPages: @escaping @Sendable (UUID, [ReceiptPage]) async throws -> ReceiptDocument = {
      _, _ in throw TestError.failed
    }
  ) -> ReceiptStorageClient {
    ReceiptStorageClient(
      create: { _, _ in document },
      createBlank: { _, _ in document },
      list: { [] },
      load: { _ in document },
      loadPages: { _ in [] },
      pageURLs: { _ in [] },
      addPages: addPages,
      deletePage: { _, _ in throw TestError.failed },
      reorderPages: { _, _ in throw TestError.failed },
      save: { document in await recorder?.append(document) },
      delete: { _ in })
  }

  private func recognizedDocument(pageCount: Int, recognizedCount: Int) -> ReceiptDocument {
    let scan = ReceiptScan(pages: [])
    let draft = ReceiptDraft(receipt: ParsedReceipt(merchantName: "Saved"), id: scan.id)
    var document = ReceiptDocument.pending(for: scan).updating(from: draft)
    document.scan.pages = (0..<pageCount).map { _ in
      ReceiptDocument.Page(id: UUID(), file: "pages/page.heic", mediaType: "image/heic")
    }
    document.recognition.pageIDs = document.scan.pages.prefix(recognizedCount).map(\.id)
    return document
  }

  private func failingClient() -> ReceiptParsingClient {
    ReceiptParsingClient(usesSampleData: false) { _ in
      throw TestError.failed
    }
  }

  private func offlineClient() -> ReceiptParsingClient {
    ReceiptParsingClient(usesSampleData: false) { _ in
      throw ReceiptParserError.connectionUnavailable
    }
  }

  private func unavailableClient(parser: FlowParseRecorder? = nil) -> ReceiptParsingClient {
    ReceiptParsingClient(
      usesSampleData: false,
      stream: { _, _ in
        _ = await parser?.parse()
        throw ReceiptParserError.modelUnavailable("Unavailable.")
      },
      status: { .unavailable("Unavailable.") })
  }

  private func rescanningClient() -> ReceiptParsingClient {
    ReceiptParsingClient(usesSampleData: false) { _ in
      ParsedReceipt(merchantName: "Rescanned")
    }
  }

  private func blankDocument(id: UUID) -> ReceiptDocument {
    let scan = ReceiptScan(id: id, pages: [], source: .manual)
    let draft = ReceiptDraft(receipt: ParsedReceipt(), id: id, backgroundStyle: .blue)
    return ReceiptDocument.pending(for: scan).updating(from: draft)
  }
}

private final class FlowPrewarmCounter: Sendable {
  private let value = Mutex(0)

  var count: Int { value.withLock { $0 } }

  func increment() {
    value.withLock { $0 += 1 }
  }
}

private actor FlowParseRecorder {
  private(set) var count = 0

  func parse() -> ParsedReceipt {
    count += 1
    return ParsedReceipt(merchantName: "Saved")
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
