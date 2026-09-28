#if !SWIFT_PACKAGE
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

    func testCreateInputCreatesBlankReviewDraft() async {
      let id = UUID()
      let document = blankDocument(id: id)
      let storage = storage(document: document)
      let model = ReceiptFlowModel(input: .create(id: id))

      await model.performWork(using: center(storage: storage), storage: storage)

      let draft = try? XCTUnwrap(model.reviewingDraft)
      XCTAssertEqual(model.document?.id, id)
      XCTAssertEqual(model.document?.scan.source, .manual)
      XCTAssertEqual(draft?.merchantName, "")
      XCTAssertEqual(draft?.items.isEmpty, true)
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
        throw FlowTestError.failed
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
      let storage = storage(document: pendingDocument(for: ReceiptScan(pages: [])))
      let failingStorage = ReceiptStorageClient(
        create: storage.create,
        createBlank: storage.createBlank,
        list: storage.list,
        load: { _ in throw FlowTestError.failed },
        loadPages: storage.loadPages,
        pageURLs: storage.pageURLs,
        addPages: storage.addPages,
        deletePage: storage.deletePage,
        reorderPages: storage.reorderPages,
        save: storage.save,
        delete: storage.delete)

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
      let recorder = FlowSaveRecorder()
      let storage = storage(document: pendingDocument(for: scan), recorder: recorder)
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
      var pending = pendingDocument(for: scan)
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
      let recorder = FlowSaveRecorder()
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
      let failingStorage = ReceiptStorageClient(
        create: storage.create,
        createBlank: storage.createBlank,
        list: storage.list,
        load: { _ in throw FlowTestError.failed },
        loadPages: storage.loadPages,
        pageURLs: storage.pageURLs,
        addPages: storage.addPages,
        deletePage: storage.deletePage,
        reorderPages: storage.reorderPages,
        save: storage.save,
        delete: storage.delete)

      await model.enterManually(storage: failingStorage)

      guard case .failed(let failure) = model.phase else {
        return XCTFail("Expected failed phase")
      }
      XCTAssertTrue(failure.allowsManualEntry)
    }

    func testLoadFailureCanRetrySameReceipt() async {
      let id = UUID()
      let model = ReceiptFlowModel(input: .storedReceipt(id))
      let storage = ReceiptStorageClient(
        create: { _, _ in throw FlowTestError.failed },
        createBlank: { _, _ in throw FlowTestError.failed },
        list: { [] },
        load: { _ in throw FlowTestError.failed },
        loadPages: { _ in throw FlowTestError.failed },
        pageURLs: { _ in [] },
        addPages: { _, _ in throw FlowTestError.failed },
        deletePage: { _, _ in throw FlowTestError.failed },
        reorderPages: { _, _ in throw FlowTestError.failed },
        save: { _ in },
        delete: { _ in })
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
      let pending = pendingDocument(for: scan)
      let parser = FlowParseRecorder()
      let saves = FlowFailingSaveSequence(failures: 1)
      let storage = ReceiptStorageClient(
        create: { _, _ in pending },
        createBlank: { _, _ in pending },
        list: { [] },
        load: { _ in pending },
        loadPages: { _ in [] },
        pageURLs: { _ in [] },
        addPages: { _, _ in throw FlowTestError.failed },
        deletePage: { _, _ in throw FlowTestError.failed },
        reorderPages: { _, _ in throw FlowTestError.failed },
        save: { document in
          if document.recognition.status == .succeeded {
            try await saves.save(document)
          }
        },
        delete: { _ in })
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
      let completed = pendingDocument(for: scan).updating(from: draft)
      let storage = storage(document: completed)
      let model = ReceiptFlowModel(input: .storedReceipt(scan.id))

      await model.performWork(using: center(storage: storage), storage: storage)

      XCTAssertEqual(model.reviewingDraft?.merchantName, "Saved")
      XCTAssertEqual(model.backgroundStyle, completed.presentation.backgroundStyle)
    }

    func testStoredPendingReceiptStartsRecognizing() async {
      let scan = ReceiptScan(pages: [])
      let storage = storage(for: scan)
      let model = ReceiptFlowModel(input: .storedReceipt(scan.id))

      await model.performWork(using: center(storage: storage), storage: storage)

      guard case .recognizing(let recognition) = model.phase else {
        return XCTFail("Expected recognizing phase")
      }
      XCTAssertEqual(recognition.id, scan.id)
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
      let recorder = FlowSaveRecorder()
      let (model, storage) = await reviewingModel(merchantName: "Saved", recorder: recorder)
      let draft = try XCTUnwrap(model.reviewingDraft)

      draft.merchantName = "Updated"
      await model.autosave(storage: storage)

      let saved = await recorder.documents
      XCTAssertEqual(saved.last?.receipt?.merchant.name, "Updated")
    }

    func testFlushWritesWithoutDebounce() async throws {
      let recorder = FlowSaveRecorder()
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
      let recorder = FlowSaveRecorder()
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
      let recorder = FlowSaveRecorder()
      let storage = storage(document: document, recorder: recorder)
      let failingClient = ReceiptParsingClient(usesSampleData: false) { _ in
        throw FlowTestError.failed
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
      recorder: FlowSaveRecorder? = nil
    ) async -> (ReceiptFlowModel, ReceiptStorageClient) {
      let scan = ReceiptScan(pages: [])
      let draft = ReceiptDraft(receipt: ParsedReceipt(merchantName: merchantName), id: scan.id)
      let completed = pendingDocument(for: scan).updating(from: draft)
      let storage = storage(document: completed, recorder: recorder)
      let model = ReceiptFlowModel(input: .storedReceipt(scan.id))
      await model.performWork(using: center(storage: storage), storage: storage)
      return (model, storage)
    }

    private func center(
      parsingClient: ReceiptParsingClient = .sample(pacing: .zero),
      storage: ReceiptStorageClient
    ) -> ReceiptRecognitionCenter {
      ReceiptRecognitionCenter(
        parsingClient: parsingClient,
        storage: storage,
        connectivity: .immediate,
        connectionRetryDelay: .zero)
    }

    private func storage(for scan: ReceiptScan) -> ReceiptStorageClient {
      storage(document: pendingDocument(for: scan))
    }

    private func storage(
      document: ReceiptDocument,
      recorder: FlowSaveRecorder? = nil,
      addPages: @escaping @Sendable (UUID, [ReceiptPage]) async throws -> ReceiptDocument = {
        _, _ in throw FlowTestError.failed
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
        deletePage: { _, _ in throw FlowTestError.failed },
        reorderPages: { _, _ in throw FlowTestError.failed },
        save: { document in await recorder?.append(document) },
        delete: { _ in })
    }

    private func recognizedDocument(pageCount: Int, recognizedCount: Int) -> ReceiptDocument {
      let scan = ReceiptScan(pages: [])
      let draft = ReceiptDraft(receipt: ParsedReceipt(merchantName: "Saved"), id: scan.id)
      var document = pendingDocument(for: scan).updating(from: draft)
      document.scan.pages = (0..<pageCount).map { _ in
        ReceiptDocument.Page(id: UUID(), file: "pages/page.heic", mediaType: "image/heic")
      }
      document.recognition.pageIDs = document.scan.pages.prefix(recognizedCount).map(\.id)
      return document
    }

    private func failingClient() -> ReceiptParsingClient {
      ReceiptParsingClient(usesSampleData: false) { _ in
        throw FlowTestError.failed
      }
    }

    private func rescanningClient(merchantName: String = "Rescanned") -> ReceiptParsingClient {
      ReceiptParsingClient(usesSampleData: false) { _ in
        ParsedReceipt(merchantName: merchantName)
      }
    }

    private func pendingDocument(for scan: ReceiptScan) -> ReceiptDocument {
      ReceiptDocument(
        schemaVersion: 1,
        id: scan.id,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        presentation: .init(backgroundStyle: .blue),
        scan: .init(capturedAt: scan.capturedAt, source: scan.source, pages: []),
        recognition: .init(
          status: .pending,
          contractVersion: 1,
          lastAttemptedAt: nil,
          completedAt: nil,
          warnings: [],
          failureMessage: nil),
        receipt: nil,
        split: nil)
    }

    private func blankDocument(id: UUID) -> ReceiptDocument {
      let scan = ReceiptScan(id: id, pages: [], source: .manual)
      let draft = ReceiptDraft(receipt: ParsedReceipt(), id: id, backgroundStyle: .blue)
      return pendingDocument(for: scan).updating(from: draft)
    }
  }

  private enum FlowTestError: Error {
    case failed
  }

  private actor FlowSaveRecorder {
    private(set) var documents: [ReceiptDocument] = []

    func append(_ document: ReceiptDocument) {
      documents.append(document)
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
        throw FlowTestError.failed
      }
    }
  }
#endif
