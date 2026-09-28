#if !SWIFT_PACKAGE
  import XCTest
  @testable import open_receipt

  @MainActor
  final class ReceiptRecognitionCenterTests: XCTestCase {
    func testRecognitionPublishesStreamedPreview() async {
      let preview = ReceiptParsePreview(
        merchantName: "Juniper Market",
        items: [.init(description: "Cold Brew", lineTotal: 6.5)])
      let client = ReceiptParsingClient(
        usesSampleData: false,
        stream: { _, onPreview in
          await onPreview(preview)
          return ParsedReceipt(merchantName: "Juniper Market")
        })
      let center = makeCenter(parsingClient: client)

      let recognition = center.recognize(ReceiptScan(pages: []))
      _ = await recognition.outcome

      XCTAssertEqual(recognition.preview, preview)
    }

    func testRecognitionSucceedsWithStoredReceipt() async {
      let center = makeCenter()
      let scan = ReceiptScan(pages: [])

      let outcome = await center.recognize(scan).outcome

      guard case .recognized(let document) = outcome else {
        return XCTFail("Expected a recognized receipt")
      }
      XCTAssertEqual(document.id, scan.id)
      XCTAssertEqual(document.recognition.status, .succeeded)
      XCTAssertEqual(document.receipt?.merchant.name, "Juniper Market")
    }

    func testReadingStartsBeforeScanIsStored() async {
      let log = EventLog()
      let client = ReceiptParsingClient(usesSampleData: false) { _ in
        await log.append("parse")
        return ParsedReceipt(merchantName: "Cafe")
      }
      let storage = makeStorage(create: { scan, style in
        try await Task.sleep(for: .milliseconds(50))
        await log.append("create")
        return ReceiptRecognitionCenterTests.pendingDocument(id: scan.id, style: style)
      })
      let center = makeCenter(parsingClient: client, storage: storage)

      _ = await center.recognize(ReceiptScan(pages: [])).outcome

      let events = await log.events
      XCTAssertEqual(events, ["parse", "create"])
    }

    func testNewReceiptUsesRequestedBackgroundStyle() async {
      let center = makeCenter()

      let outcome = await center.recognize(ReceiptScan(pages: []), backgroundStyle: .peach).outcome

      guard case .recognized(let document) = outcome else {
        return XCTFail("Expected a recognized receipt")
      }
      XCTAssertEqual(document.presentation.backgroundStyle, .peach)
    }

    func testNewReceiptStartsWithOwner() async {
      let center = makeCenter(owner: ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

      let outcome = await center.recognize(ReceiptScan(pages: [])).outcome

      guard case .recognized(let document) = outcome else {
        return XCTFail("Expected a recognized receipt")
      }
      let currentUser = document.split?.participants.first { $0.source.type == .currentUser }
      XCTAssertEqual(currentUser?.displayName, "Alex")
      XCTAssertEqual(currentUser?.source.identifier, "me")
    }

    func testNewReceiptWithoutOwnerUsesDefaultName() async {
      let center = makeCenter()

      let outcome = await center.recognize(ReceiptScan(pages: [])).outcome

      guard case .recognized(let document) = outcome else {
        return XCTFail("Expected a recognized receipt")
      }
      let currentUser = document.split?.participants.first { $0.source.type == .currentUser }
      XCTAssertEqual(currentUser?.displayName, "Me")
      XCTAssertNil(currentUser?.source.identifier)
    }

    func testRescanKeepsReceiptCurrentUser() async {
      let scan = ReceiptScan(pages: [])
      let previous = ReceiptDraft(receipt: ParsedReceipt(merchantName: "Old"), id: scan.id)
      let stored = Self.pendingDocument(id: scan.id, style: .mint).updating(from: previous)
      let center = makeCenter(owner: ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

      let outcome = await center.recognize(scan, replacing: stored).outcome

      guard case .recognized(let document) = outcome else {
        return XCTFail("Expected a recognized receipt")
      }
      let currentUser = document.split?.participants.first { $0.source.type == .currentUser }
      XCTAssertEqual(currentUser?.displayName, "Me")
    }

    func testConnectionFailureWaitsForConnectionAndReadsAgain() async {
      let attempts = EventLog()
      let client = ReceiptParsingClient(usesSampleData: false) { _ in
        await attempts.append("attempt")
        if await attempts.events.count == 1 { throw ReceiptParserError.connectionUnavailable }
        return ParsedReceipt(merchantName: "Cafe")
      }
      let center = makeCenter(parsingClient: client)

      let outcome = await center.recognize(ReceiptScan(pages: [])).outcome

      guard case .recognized = outcome else {
        return XCTFail("Expected a recognized receipt")
      }
      let count = await attempts.events.count
      XCTAssertEqual(count, 2)
    }

    func testRepeatedConnectionFailuresEventuallyFail() async {
      let client = ReceiptParsingClient(usesSampleData: false) { _ in
        throw ReceiptParserError.connectionUnavailable
      }
      let center = makeCenter(parsingClient: client)

      let outcome = await center.recognize(ReceiptScan(pages: [])).outcome

      guard case .failed(_, let isRetryable) = outcome else {
        return XCTFail("Expected a failure")
      }
      XCTAssertTrue(isRetryable)
    }

    func testFailedReadRecordsFailureOnNewReceipt() async {
      let recorder = SaveRecorder()
      let client = ReceiptParsingClient(usesSampleData: false) { _ in
        throw ReceiptParserError.timedOut
      }
      let center = makeCenter(
        parsingClient: client,
        storage: makeStorage(save: { await recorder.append($0) }))

      _ = await center.recognize(ReceiptScan(pages: [])).outcome

      let saved = await recorder.documents
      XCTAssertEqual(saved.last?.recognition.status, .failed)
      XCTAssertEqual(
        saved.last?.recognition.failureMessage, ReceiptParserError.timedOut.localizedDescription)
    }

    func testFinishedRecognitionLeavesCenter() async {
      let center = makeCenter()
      let recognition = center.recognize(ReceiptScan(pages: []))

      _ = await recognition.outcome

      XCTAssertNil(center.recognition(for: recognition.id))
      XCTAssertEqual(center.finishedCount, 1)
      XCTAssertEqual(recognition.status, .finished)
    }

    func testRecognizingSameScanTwiceReturnsActiveRecognition() {
      let center = makeCenter()
      let scan = ReceiptScan(pages: [])

      let first = center.recognize(scan)
      let second = center.recognize(scan)

      XCTAssertTrue(first === second)
    }

    private func makeCenter(
      parsingClient: ReceiptParsingClient = .sample(pacing: .zero),
      storage: ReceiptStorageClient? = nil,
      owner: ReceiptOwner? = nil
    ) -> ReceiptRecognitionCenter {
      ReceiptRecognitionCenter(
        parsingClient: parsingClient,
        storage: storage ?? makeStorage(),
        owner: { owner },
        connectivity: .immediate,
        connectionRetryDelay: .zero)
    }

    private func makeStorage(
      create:
        @escaping @Sendable (ReceiptScan, ReceiptBackgroundStyle) async throws
        -> ReceiptDocument = { scan, style in
          ReceiptRecognitionCenterTests.pendingDocument(id: scan.id, style: style)
        },
      save: @escaping @Sendable (ReceiptDocument) async throws -> Void = { _ in }
    ) -> ReceiptStorageClient {
      ReceiptStorageClient(
        create: create,
        createBlank: { _, _ in throw TestError.unused },
        list: { [] },
        load: { _ in throw TestError.unused },
        loadPages: { _ in [] },
        pageURLs: { _ in [] },
        addPages: { _, _ in throw TestError.unused },
        deletePage: { _, _ in throw TestError.unused },
        reorderPages: { _, _ in throw TestError.unused },
        save: save,
        delete: { _ in })
    }

    private nonisolated static func pendingDocument(
      id: UUID,
      style: ReceiptBackgroundStyle
    ) -> ReceiptDocument {
      ReceiptDocument(
        schemaVersion: ReceiptDocument.currentSchemaVersion,
        id: id,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        presentation: .init(backgroundStyle: style),
        scan: .init(capturedAt: Date(timeIntervalSince1970: 1), source: .documentCamera, pages: []),
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
  }

  private enum TestError: Error {
    case unused
  }

  private actor EventLog {
    private(set) var events: [String] = []

    func append(_ event: String) {
      events.append(event)
    }
  }

  private actor SaveRecorder {
    private(set) var documents: [ReceiptDocument] = []

    func append(_ document: ReceiptDocument) {
      documents.append(document)
    }
  }
#endif
