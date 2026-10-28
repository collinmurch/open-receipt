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
      stream: { _, onPreview in
        await onPreview(preview)
        return ParsedReceipt(merchantName: "Juniper Market")
      })
    let center = ReceiptRecognitionCenter.testing(parsingClient: client)

    let recognition = center.recognize(ReceiptScan(pages: []))
    _ = await recognition.outcome

    XCTAssertEqual(recognition.preview, preview)
  }

  func testRecognitionSucceedsWithStoredReceipt() async {
    let center = ReceiptRecognitionCenter.testing()
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
    let log = Recorder<String>()
    let client = ReceiptParsingClient { _ in
      await log.append("parse")
      return ParsedReceipt(merchantName: "Cafe")
    }
    var storage = ReceiptStorageClient.recognizing()
    storage.create = { scan, style in
      try await Task.sleep(for: .milliseconds(50))
      await log.append("create")
      return ReceiptDocument.pending(id: scan.id, style: style)
    }
    let center = ReceiptRecognitionCenter.testing(parsingClient: client, storage: storage)

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    let events = await log.values
    XCTAssertEqual(events, ["parse", "create"])
  }

  func testNewReceiptUsesRequestedBackgroundStyle() async {
    let center = ReceiptRecognitionCenter.testing()

    let outcome = await center.recognize(ReceiptScan(pages: []), backgroundStyle: .peach).outcome

    guard case .recognized(let document) = outcome else {
      return XCTFail("Expected a recognized receipt")
    }
    XCTAssertEqual(document.presentation.backgroundStyle, .peach)
  }

  func testNewReceiptStartsWithOwner() async {
    let center = ReceiptRecognitionCenter.testing(
      owner: ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

    let outcome = await center.recognize(ReceiptScan(pages: [])).outcome

    guard case .recognized(let document) = outcome else {
      return XCTFail("Expected a recognized receipt")
    }
    let currentUser = document.split?.participants.first { $0.source.type == .currentUser }
    XCTAssertEqual(currentUser?.displayName, "Alex")
    XCTAssertEqual(currentUser?.source.identifier, "me")
  }

  func testNewReceiptWithoutOwnerUsesDefaultName() async {
    let center = ReceiptRecognitionCenter.testing()

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
    let stored = ReceiptDocument.pending(id: scan.id, style: .mint).updating(from: previous)
    let center = ReceiptRecognitionCenter.testing(
      owner: ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

    let outcome = await center.recognize(scan, replacing: stored).outcome

    guard case .recognized(let document) = outcome else {
      return XCTFail("Expected a recognized receipt")
    }
    let currentUser = document.split?.participants.first { $0.source.type == .currentUser }
    XCTAssertEqual(currentUser?.displayName, "Me")
  }

  func testConnectionFailureWaitsForConnectionAndReadsAgain() async {
    let attempts = Recorder<String>()
    let client = ReceiptParsingClient { _ in
      await attempts.append("attempt")
      if await attempts.values.count == 1 { throw ReceiptParserError.connectionUnavailable }
      return ParsedReceipt(merchantName: "Cafe")
    }
    let center = ReceiptRecognitionCenter.testing(parsingClient: client)

    let outcome = await center.recognize(ReceiptScan(pages: [])).outcome

    guard case .recognized = outcome else {
      return XCTFail("Expected a recognized receipt")
    }
    let count = await attempts.values.count
    XCTAssertEqual(count, 2)
  }

  func testRepeatedConnectionFailuresEventuallyFail() async {
    let client = ReceiptParsingClient { _ in
      throw ReceiptParserError.connectionUnavailable
    }
    let center = ReceiptRecognitionCenter.testing(parsingClient: client)

    let outcome = await center.recognize(ReceiptScan(pages: [])).outcome

    guard case .failed(_, let isRetryable) = outcome else {
      return XCTFail("Expected a failure")
    }
    XCTAssertTrue(isRetryable)
  }

  func testCancellingReadWaitingForConnectionStopsIt() async {
    let client = ReceiptParsingClient { _ in
      throw ReceiptParserError.connectionUnavailable
    }
    let center = ReceiptRecognitionCenter.testing(parsingClient: client, connectivity: .offline)
    let recognition = center.recognize(ReceiptScan(pages: []))

    await center.cancel(recognition)

    guard case .cancelled = await recognition.outcome else {
      return XCTFail("Expected a cancelled read")
    }
    XCTAssertNil(center.recognition(for: recognition.id))
  }

  func testCancelledReadDoesNotRecordFailure() async {
    let recorder = Recorder<ReceiptDocument>()
    let client = ReceiptParsingClient { _ in
      throw ReceiptParserError.connectionUnavailable
    }
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: client,
      storage: .recognizing(recorder: recorder),
      connectivity: .offline)

    await center.cancel(center.recognize(ReceiptScan(pages: [])))

    let saved = await recorder.values
    XCTAssertTrue(saved.isEmpty)
  }

  func testFailedReadRecordsFailureOnNewReceipt() async {
    let recorder = Recorder<ReceiptDocument>()
    let client = ReceiptParsingClient { _ in
      throw ReceiptParserError.timedOut
    }
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: client,
      storage: .recognizing(recorder: recorder))

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    let saved = await recorder.values
    XCTAssertEqual(saved.last?.recognition.status, .failed)
    XCTAssertEqual(
      saved.last?.recognition.failureMessage, ReceiptParserError.timedOut.localizedDescription)
  }

  func testReadAtReadingLimitDoesNotCallModel() async {
    let log = Recorder<String>()
    let client = ReceiptParsingClient(
      stream: { _, _ in
        await log.append("parse")
        return ParsedReceipt(merchantName: "Cafe")
      },
      status: { .limitReached(resetDate: nil, canIncreaseLimit: false) })
    let center = ReceiptRecognitionCenter.testing(parsingClient: client)

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    let events = await log.values
    XCTAssertEqual(events, [])
  }

  func testReadAtReadingLimitIsDeferredUntilReset() async {
    let recorder = Recorder<ReceiptDocument>()
    let resetDate = Date().addingTimeInterval(3600)
    let client = ReceiptParsingClient(
      stream: { _, _ in ParsedReceipt(merchantName: "Cafe") },
      status: { .limitReached(resetDate: resetDate, canIncreaseLimit: false) })
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: client,
      storage: .recognizing(recorder: recorder))

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    let saved = await recorder.values
    XCTAssertEqual(saved.last?.recognition.status, .failed)
    XCTAssertEqual(saved.last?.recognition.deferredUntil, resetDate)
  }

  func testQuotaFailureIsDeferred() async {
    let recorder = Recorder<ReceiptDocument>()
    let resetDate = Date().addingTimeInterval(600)
    let client = ReceiptParsingClient { _ in
      throw ReceiptParserError.quotaLimitReached(resetDate: resetDate)
    }
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: client,
      storage: .recognizing(recorder: recorder))

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    let saved = await recorder.values
    XCTAssertEqual(saved.last?.recognition.deferredUntil, resetDate)
  }

  func testOtherFailuresAreNotDeferred() async {
    let recorder = Recorder<ReceiptDocument>()
    let client = ReceiptParsingClient { _ in
      throw ReceiptParserError.timedOut
    }
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: client,
      storage: .recognizing(recorder: recorder))

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    let saved = await recorder.values
    XCTAssertNil(saved.last?.recognition.deferredUntil)
  }

  func testResumeReadsDeferredReceiptThatIsDue() async throws {
    let recorder = Recorder<ReceiptDocument>()
    let document = Self.deferredDocument(until: Date().addingTimeInterval(-60))
    let center = try ReceiptRecognitionCenter.testing(
      storage: makeDeferredStorage(document: document, recorder: recorder))

    await center.resumeDeferredReads()

    let saved = await recorder.values
    XCTAssertEqual(saved.last?.id, document.id)
    XCTAssertEqual(saved.last?.recognition.status, .succeeded)
    XCTAssertNil(saved.last?.recognition.deferredUntil)
  }

  func testResumeWaitsForDeferredReceiptThatIsNotDue() async throws {
    let recorder = Recorder<ReceiptDocument>()
    let document = Self.deferredDocument(until: Date().addingTimeInterval(3600))
    let center = try ReceiptRecognitionCenter.testing(
      storage: makeDeferredStorage(document: document, recorder: recorder))

    await center.resumeDeferredReads()

    let saved = await recorder.values
    XCTAssertTrue(saved.isEmpty)
  }

  func testResumeWaitsWhileReadingLimitIsReached() async throws {
    let recorder = Recorder<ReceiptDocument>()
    let document = Self.deferredDocument(until: Date().addingTimeInterval(-60))
    let client = ReceiptParsingClient(
      stream: { _, _ in ParsedReceipt(merchantName: "Cafe") },
      status: { .limitReached(resetDate: nil, canIncreaseLimit: false) })
    let center = try ReceiptRecognitionCenter.testing(
      parsingClient: client,
      storage: makeDeferredStorage(document: document, recorder: recorder))

    await center.resumeDeferredReads()

    let saved = await recorder.values
    XCTAssertTrue(saved.isEmpty)
  }

  func testDeferredReadIsNotUserInitiated() async throws {
    let document = Self.deferredDocument(until: Date().addingTimeInterval(-60))
    let client = ReceiptParsingClient { _ in
      try await Task.sleep(for: .seconds(10))
      return ParsedReceipt(merchantName: "Cafe")
    }
    let center = try ReceiptRecognitionCenter.testing(
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
    let center = ReceiptRecognitionCenter.testing()
    let recognition = center.recognize(ReceiptScan(pages: []))

    _ = await recognition.outcome

    XCTAssertNil(center.recognition(for: recognition.id))
    XCTAssertEqual(center.finishedCount, 1)
    XCTAssertEqual(recognition.status, .finished)
  }

  func testRecognizingSameScanTwiceReturnsActiveRecognition() {
    let center = ReceiptRecognitionCenter.testing()
    let scan = ReceiptScan(pages: [])

    let first = center.recognize(scan)
    let second = center.recognize(scan)

    XCTAssertTrue(first === second)
  }

  func testReadUsesFreeRead() async {
    let access = lockedAccess()
    let center = ReceiptRecognitionCenter.testing(access: access)

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit - 1)
  }

  func testUnlockedReadUsesNoFreeRead() async {
    let access = ReadingAccess(client: .fixed(isEntitled: true), store: .memory(), isUnlocked: true)
    let center = ReceiptRecognitionCenter.testing(access: access)

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit)
  }

  func testReadWithoutFreeReadsNeedsUnlock() async {
    let center = ReceiptRecognitionCenter.testing(
      access: lockedAccess(used: ReadingAccess.freeReadLimit))

    let outcome = await center.recognize(ReceiptScan(pages: [])).outcome

    guard case .needsUnlock = outcome else {
      return XCTFail("Expected the read to need unlimited reading")
    }
  }

  func testReadWithoutFreeReadsDoesNotCallModel() async {
    let log = Recorder<String>()
    let client = ReceiptParsingClient { _ in
      await log.append("parse")
      return ParsedReceipt(merchantName: "Cafe")
    }
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: client, access: lockedAccess(used: ReadingAccess.freeReadLimit))

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    let events = await log.values
    XCTAssertEqual(events, [])
  }

  func testReadWithoutFreeReadsStoresScan() async {
    let scan = ReceiptScan(pages: [])
    let center = ReceiptRecognitionCenter.testing(
      access: lockedAccess(used: ReadingAccess.freeReadLimit))
    let recognition = center.recognize(scan)

    _ = await recognition.outcome

    XCTAssertEqual(recognition.document?.id, scan.id)
    XCTAssertEqual(recognition.document?.recognition.status, .pending)
  }

  func testReadsStartedTogetherStopAtFreeLimit() async {
    let client = ReceiptParsingClient { _ in
      try await Task.sleep(for: .milliseconds(20))
      return ParsedReceipt(merchantName: "Cafe")
    }
    let center = ReceiptRecognitionCenter.testing(
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
    let client = ReceiptParsingClient { _ in
      throw ReceiptParserError.timedOut
    }
    let center = ReceiptRecognitionCenter.testing(parsingClient: client, access: access)

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit)
  }

  func testDeferredReadKeepsFreeRead() async {
    let access = lockedAccess()
    let client = ReceiptParsingClient { _ in
      throw ReceiptParserError.quotaLimitReached(resetDate: Date().addingTimeInterval(600))
    }
    let center = ReceiptRecognitionCenter.testing(parsingClient: client, access: access)

    _ = await center.recognize(ReceiptScan(pages: [])).outcome

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit - 1)
  }

  func testReadCancelledBeforeItemsReturnsFreeRead() async {
    let access = lockedAccess()
    let client = ReceiptParsingClient { _ in
      throw ReceiptParserError.connectionUnavailable
    }
    let center = ReceiptRecognitionCenter.testing(
      parsingClient: client, access: access, connectivity: .offline)

    await center.cancel(center.recognize(ReceiptScan(pages: [])))

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit)
  }

  func testReadCancelledAfterItemsKeepsFreeRead() async {
    let access = lockedAccess()
    let client = ReceiptParsingClient(
      stream: { _, onPreview in
        await onPreview(ReceiptParsePreview(items: [.init(description: "Cold Brew")]))
        try await Task.sleep(for: .seconds(3600))
        return ParsedReceipt(merchantName: "Cafe")
      })
    let center = ReceiptRecognitionCenter.testing(parsingClient: client, access: access)
    let recognition = center.recognize(ReceiptScan(pages: []))
    while !recognition.hasShownItems {
      await Task.yield()
    }

    await center.cancel(recognition)

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit - 1)
  }

  func testResumedDeferredReadUsesNoNewFreeRead() async throws {
    let recorder = Recorder<ReceiptDocument>()
    let document = Self.deferredDocument(until: Date().addingTimeInterval(-60))
    let key = ReceiptRecognitionCenter.readKey(
      for: ReceiptRecognition(
        scan: ReceiptScan(id: document.id, pages: []),
        backgroundStyle: .blue,
        document: document))
    let others = (1..<ReadingAccess.freeReadLimit).map { "other-\($0)" }
    let access = ReadingAccess(
      client: .fixed(isEntitled: false), store: .memory(Set([key] + others)), isUnlocked: false)
    let center = try ReceiptRecognitionCenter.testing(
      storage: makeDeferredStorage(document: document, recorder: recorder),
      access: access)

    await center.resumeDeferredReads()

    let saved = await recorder.values
    XCTAssertEqual(saved.last?.recognition.status, .succeeded)
  }

  func testDeferredReadWithoutFreeReadsStopsWaiting() async throws {
    let recorder = Recorder<ReceiptDocument>()
    let document = Self.deferredDocument(until: Date().addingTimeInterval(-60))
    let center = try ReceiptRecognitionCenter.testing(
      storage: makeDeferredStorage(document: document, recorder: recorder),
      access: lockedAccess(used: ReadingAccess.freeReadLimit))

    await center.resumeDeferredReads()

    let saved = await recorder.values
    XCTAssertEqual(saved.last?.id, document.id)
    XCTAssertNil(saved.last?.recognition.deferredUntil)
    XCTAssertEqual(saved.last?.recognition.status, .failed)
  }

  func testReadsOfSameReceiptShareReadKey() {
    let scan = ReceiptScan(pages: [])
    let first = ReceiptRecognition(scan: scan, backgroundStyle: .blue)
    let retry = ReceiptRecognition(
      scan: scan, backgroundStyle: .blue, document: .pending(id: scan.id, style: .blue))

    XCTAssertEqual(
      ReceiptRecognitionCenter.readKey(for: first), ReceiptRecognitionCenter.readKey(for: retry))
  }

  func testRescanHasNewReadKey() {
    let scan = ReceiptScan(pages: [])
    let draft = ReceiptDraft(receipt: ParsedReceipt(merchantName: "Old"), id: scan.id)
    let stored = ReceiptDocument.pending(id: scan.id, style: .mint).updating(from: draft)
    let first = ReceiptRecognition(scan: scan, backgroundStyle: .mint)
    let rescan = ReceiptRecognition(scan: scan, backgroundStyle: .mint, document: stored)

    XCTAssertNotEqual(
      ReceiptRecognitionCenter.readKey(for: first), ReceiptRecognitionCenter.readKey(for: rescan))
  }

  private func makeDeferredStorage(
    document: ReceiptDocument,
    recorder: Recorder<ReceiptDocument>? = nil
  ) throws -> ReceiptStorageClient {
    let summary = try ReceiptSummary(document)
    let page = Self.page()
    var storage = ReceiptStorageClient.recognizing(recorder: recorder)
    storage.list = { [summary] }
    storage.load = { _ in document }
    storage.loadPages = { _ in [page] }
    return storage
  }

  private nonisolated static func deferredDocument(until date: Date) -> ReceiptDocument {
    var document = ReceiptDocument.pending(style: .blue)
    document.scan.pages = [
      ReceiptDocument.Page(id: UUID(), file: "pages/page.heic", mediaType: "image/heic")
    ]
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
}
