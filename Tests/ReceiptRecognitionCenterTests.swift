import CoreGraphics
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

  func testCancellingReadWaitingForConnectionStopsIt() async {
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      throw ReceiptParserError.connectionUnavailable
    }
    let center = makeCenter(parsingClient: client, connectivity: .offline)
    let recognition = center.recognize(ReceiptScan(pages: []))

    await center.cancel(recognition)

    guard case .cancelled = await recognition.outcome else {
      return XCTFail("Expected a cancelled read")
    }
    XCTAssertNil(center.recognition(for: recognition.id))
  }

  func testCancelledReadDoesNotRecordFailure() async {
    let recorder = SaveRecorder()
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      throw ReceiptParserError.connectionUnavailable
    }
    let center = makeCenter(
      parsingClient: client,
      storage: makeStorage(save: { await recorder.append($0) }),
      connectivity: .offline)

    await center.cancel(center.recognize(ReceiptScan(pages: [])))

    let saved = await recorder.documents
    XCTAssertTrue(saved.isEmpty)
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

  func testReadAtReadingLimitDoesNotCallModel() async {
    let log = EventLog()
    let client = ReceiptParsingClient(
      usesSampleData: false,
      stream: { _, _ in
        await log.append("parse")
        return ParsedReceipt(merchantName: "Cafe")
      },
      status: { .limitReached(resetDate: nil, canIncreaseLimit: false) })
    let center = makeCenter(parsingClient: client)

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    let events = await log.events
    XCTAssertEqual(events, [])
  }

  func testReadAtReadingLimitIsDeferredUntilReset() async {
    let recorder = SaveRecorder()
    let resetDate = Date().addingTimeInterval(3600)
    let client = ReceiptParsingClient(
      usesSampleData: false,
      stream: { _, _ in ParsedReceipt(merchantName: "Cafe") },
      status: { .limitReached(resetDate: resetDate, canIncreaseLimit: false) })
    let center = makeCenter(
      parsingClient: client,
      storage: makeStorage(save: { await recorder.append($0) }))

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    let saved = await recorder.documents
    XCTAssertEqual(saved.last?.recognition.status, .failed)
    XCTAssertEqual(saved.last?.recognition.deferredUntil, resetDate)
  }

  func testQuotaFailureIsDeferred() async {
    let recorder = SaveRecorder()
    let resetDate = Date().addingTimeInterval(600)
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      throw ReceiptParserError.quotaLimitReached(resetDate: resetDate)
    }
    let center = makeCenter(
      parsingClient: client,
      storage: makeStorage(save: { await recorder.append($0) }))

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    let saved = await recorder.documents
    XCTAssertEqual(saved.last?.recognition.deferredUntil, resetDate)
  }

  func testOtherFailuresAreNotDeferred() async {
    let recorder = SaveRecorder()
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      throw ReceiptParserError.timedOut
    }
    let center = makeCenter(
      parsingClient: client,
      storage: makeStorage(save: { await recorder.append($0) }))

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    let saved = await recorder.documents
    XCTAssertNil(saved.last?.recognition.deferredUntil)
  }

  func testResumeReadsDeferredReceiptThatIsDue() async {
    let recorder = SaveRecorder()
    let document = Self.deferredDocument(until: Date().addingTimeInterval(-60))
    let center = makeCenter(
      storage: makeDeferredStorage(document: document, save: { await recorder.append($0) }))

    await center.resumeDeferredReads()

    let saved = await recorder.documents
    XCTAssertEqual(saved.last?.id, document.id)
    XCTAssertEqual(saved.last?.recognition.status, .succeeded)
    XCTAssertNil(saved.last?.recognition.deferredUntil)
  }

  func testResumeWaitsForDeferredReceiptThatIsNotDue() async {
    let recorder = SaveRecorder()
    let document = Self.deferredDocument(until: Date().addingTimeInterval(3600))
    let center = makeCenter(
      storage: makeDeferredStorage(document: document, save: { await recorder.append($0) }))

    await center.resumeDeferredReads()

    let saved = await recorder.documents
    XCTAssertTrue(saved.isEmpty)
  }

  func testResumeWaitsWhileReadingLimitIsReached() async {
    let recorder = SaveRecorder()
    let document = Self.deferredDocument(until: Date().addingTimeInterval(-60))
    let client = ReceiptParsingClient(
      usesSampleData: false,
      stream: { _, _ in ParsedReceipt(merchantName: "Cafe") },
      status: { .limitReached(resetDate: nil, canIncreaseLimit: false) })
    let center = makeCenter(
      parsingClient: client,
      storage: makeDeferredStorage(document: document, save: { await recorder.append($0) }))

    await center.resumeDeferredReads()

    let saved = await recorder.documents
    XCTAssertTrue(saved.isEmpty)
  }

  func testDeferredReadIsNotUserInitiated() async {
    let document = Self.deferredDocument(until: Date().addingTimeInterval(-60))
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      try await Task.sleep(for: .seconds(10))
      return ParsedReceipt(merchantName: "Cafe")
    }
    let center = makeCenter(
      parsingClient: client, storage: makeDeferredStorage(document: document))

    let resume = Task { await center.resumeDeferredReads() }
    while center.recognition(for: document.id) == nil {
      await Task.yield()
    }

    XCTAssertEqual(center.recognition(for: document.id)?.isUserInitiated, false)
    resume.cancel()
    center.recognition(for: document.id)?.task?.cancel()
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

  func testReadUsesFreeRead() async {
    let access = lockedAccess()
    let center = makeCenter(access: access)

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit - 1)
  }

  func testUnlockedReadUsesNoFreeRead() async {
    let access = ReadingAccess(client: .fixed(isEntitled: true), store: .memory(), isUnlocked: true)
    let center = makeCenter(access: access)

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit)
  }

  func testReadWithoutFreeReadsNeedsUnlock() async {
    let center = makeCenter(access: lockedAccess(used: ReadingAccess.freeReadLimit))

    let outcome = await center.recognize(ReceiptScan(pages: [])).outcome

    guard case .needsUnlock = outcome else {
      return XCTFail("Expected the read to need unlimited reading")
    }
  }

  func testReadWithoutFreeReadsDoesNotCallModel() async {
    let log = EventLog()
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      await log.append("parse")
      return ParsedReceipt(merchantName: "Cafe")
    }
    let center = makeCenter(
      parsingClient: client, access: lockedAccess(used: ReadingAccess.freeReadLimit))

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    let events = await log.events
    XCTAssertEqual(events, [])
  }

  func testReadWithoutFreeReadsStoresScan() async {
    let scan = ReceiptScan(pages: [])
    let center = makeCenter(access: lockedAccess(used: ReadingAccess.freeReadLimit))
    let recognition = center.recognize(scan)

    _ = await recognition.outcome

    XCTAssertEqual(recognition.document?.id, scan.id)
    XCTAssertEqual(recognition.document?.recognition.status, .pending)
  }

  func testReadsStartedTogetherStopAtFreeLimit() async {
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      try await Task.sleep(for: .milliseconds(20))
      return ParsedReceipt(merchantName: "Cafe")
    }
    let center = makeCenter(
      parsingClient: client, access: lockedAccess(used: ReadingAccess.freeReadLimit - 1))

    let first = center.recognize(ReceiptScan(pages: []))
    let second = center.recognize(ReceiptScan(pages: []))

    guard case .recognized = await first.outcome else {
      return XCTFail("Expected the first read to finish")
    }
    guard case .needsUnlock = await second.outcome else {
      return XCTFail("Expected the second read to need unlimited reading")
    }
  }

  func testFailedReadReturnsFreeRead() async {
    let access = lockedAccess()
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      throw ReceiptParserError.timedOut
    }
    let center = makeCenter(parsingClient: client, access: access)

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit)
  }

  func testDeferredReadKeepsFreeRead() async {
    let access = lockedAccess()
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      throw ReceiptParserError.quotaLimitReached(resetDate: Date().addingTimeInterval(600))
    }
    let center = makeCenter(parsingClient: client, access: access)

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit - 1)
  }

  func testReadCancelledBeforeItemsReturnsFreeRead() async {
    let access = lockedAccess()
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      throw ReceiptParserError.connectionUnavailable
    }
    let center = makeCenter(parsingClient: client, access: access, connectivity: .offline)

    await center.cancel(center.recognize(ReceiptScan(pages: [])))

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit)
  }

  func testReadCancelledAfterItemsKeepsFreeRead() async {
    let access = lockedAccess()
    let client = ReceiptParsingClient(
      usesSampleData: false,
      stream: { _, onPreview in
        await onPreview(ReceiptParsePreview(items: [.init(description: "Cold Brew")]))
        try await Task.sleep(for: .seconds(3600))
        return ParsedReceipt(merchantName: "Cafe")
      })
    let center = makeCenter(parsingClient: client, access: access)
    let recognition = center.recognize(ReceiptScan(pages: []))
    while !recognition.hasShownItems {
      await Task.yield()
    }

    await center.cancel(recognition)

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit - 1)
  }

  func testResumedDeferredReadUsesNoNewFreeRead() async {
    let recorder = SaveRecorder()
    let document = Self.deferredDocument(until: Date().addingTimeInterval(-60))
    let key = ReceiptRecognitionCenter.readKey(
      for: ReceiptRecognition(
        scan: ReceiptScan(id: document.id, pages: []),
        backgroundStyle: .blue,
        document: document))
    let others = (1..<ReadingAccess.freeReadLimit).map { "other-\($0)" }
    let access = ReadingAccess(
      client: .fixed(isEntitled: false), store: .memory(Set([key] + others)))
    let center = makeCenter(
      storage: makeDeferredStorage(document: document, save: { await recorder.append($0) }),
      access: access)

    await center.resumeDeferredReads()

    let saved = await recorder.documents
    XCTAssertEqual(saved.last?.recognition.status, .succeeded)
  }

  func testDeferredReadWithoutFreeReadsStopsWaiting() async {
    let recorder = SaveRecorder()
    let document = Self.deferredDocument(until: Date().addingTimeInterval(-60))
    let center = makeCenter(
      storage: makeDeferredStorage(document: document, save: { await recorder.append($0) }),
      access: lockedAccess(used: ReadingAccess.freeReadLimit))

    await center.resumeDeferredReads()

    let saved = await recorder.documents
    XCTAssertEqual(saved.last?.id, document.id)
    XCTAssertNil(saved.last?.recognition.deferredUntil)
    XCTAssertEqual(saved.last?.recognition.status, .failed)
  }

  func testReadsOfSameReceiptShareReadKey() {
    let scan = ReceiptScan(pages: [])
    let first = ReceiptRecognition(scan: scan, backgroundStyle: .blue)
    let retry = ReceiptRecognition(
      scan: scan, backgroundStyle: .blue, document: Self.pendingDocument(id: scan.id, style: .blue))

    XCTAssertEqual(
      ReceiptRecognitionCenter.readKey(for: first), ReceiptRecognitionCenter.readKey(for: retry))
  }

  func testRescanHasNewReadKey() {
    let scan = ReceiptScan(pages: [])
    let draft = ReceiptDraft(receipt: ParsedReceipt(merchantName: "Old"), id: scan.id)
    let stored = Self.pendingDocument(id: scan.id, style: .mint).updating(from: draft)
    let first = ReceiptRecognition(scan: scan, backgroundStyle: .mint)
    let rescan = ReceiptRecognition(scan: scan, backgroundStyle: .mint, document: stored)

    XCTAssertNotEqual(
      ReceiptRecognitionCenter.readKey(for: first), ReceiptRecognitionCenter.readKey(for: rescan))
  }

  private func lockedAccess(used: Int = 0) -> ReadingAccess {
    let reads = used > 0 ? Set((1...used).map { "used-\($0)" }) : []
    return ReadingAccess(client: .fixed(isEntitled: false), store: .memory(reads))
  }

  private func makeCenter(
    parsingClient: ReceiptParsingClient = .sample(pacing: .zero),
    storage: ReceiptStorageClient? = nil,
    access: ReadingAccess = .unlimited(),
    owner: ReceiptOwner? = nil,
    connectivity: ReceiptConnectivity = .immediate
  ) -> ReceiptRecognitionCenter {
    ReceiptRecognitionCenter(
      parsingClient: parsingClient,
      storage: storage ?? makeStorage(),
      access: access,
      owner: { owner },
      connectivity: connectivity,
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

  private func makeDeferredStorage(
    document: ReceiptDocument,
    save: @escaping @Sendable (ReceiptDocument) async throws -> Void = { _ in }
  ) -> ReceiptStorageClient {
    let summary = ReceiptSummary(
      id: document.id,
      updatedAt: document.updatedAt,
      capturedAt: document.scan.capturedAt,
      backgroundStyle: document.presentation.backgroundStyle,
      recognitionStatus: document.recognition.status,
      merchantName: nil,
      localDate: nil,
      total: nil,
      currency: nil,
      isUnavailable: false,
      unavailableDescription: nil,
      deferredUntil: document.recognition.deferredUntil)
    let page = Self.page()
    return ReceiptStorageClient(
      create: { _, _ in throw TestError.unused },
      createBlank: { _, _ in throw TestError.unused },
      list: { [summary] },
      load: { _ in document },
      loadPages: { _ in [page] },
      pageURLs: { _ in [] },
      addPages: { _, _ in throw TestError.unused },
      deletePage: { _, _ in throw TestError.unused },
      reorderPages: { _, _ in throw TestError.unused },
      save: save,
      delete: { _ in })
  }

  private nonisolated static func deferredDocument(until date: Date) -> ReceiptDocument {
    var document = pendingDocument(id: UUID(), style: .blue)
    document.recognition.status = .failed
    document.recognition.deferredUntil = date
    return document
  }

  private nonisolated static func page() -> ReceiptPage {
    let context = CGContext(
      data: nil,
      width: 1,
      height: 1,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    return ReceiptPage(image: context!.makeImage()!)
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

extension ReceiptConnectivity {
  /// A connection that never returns until the waiting task is cancelled.
  static let offline = ReceiptConnectivity { try? await Task.sleep(for: .seconds(3600)) }
}

private actor SaveRecorder {
  private(set) var documents: [ReceiptDocument] = []

  func append(_ document: ReceiptDocument) {
    documents.append(document)
  }
}
