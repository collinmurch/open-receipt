import CryptoKit
import Foundation
import Observation

/// Owns every receipt being read. Recognition starts the moment pages exist, writes the scan to
/// storage alongside the model request, and finishes even if the person leaves the receipt.
@MainActor
@Observable
final class ReceiptRecognitionCenter {
  private(set) var recognitions: [UUID: ReceiptRecognition] = [:]
  /// Increments whenever a recognition finishes, so the library knows to refresh.
  private(set) var finishedCount = 0

  @ObservationIgnored let parsingClient: ReceiptParsingClient
  @ObservationIgnored private let storage: ReceiptStorageClient
  @ObservationIgnored private let access: ReadingAccess
  @ObservationIgnored private let connectivity: ReceiptConnectivity
  @ObservationIgnored private let connectionRetryLimit: Int
  @ObservationIgnored private let connectionRetryDelay: Duration
  @ObservationIgnored private let owner: @Sendable () async -> ReceiptOwner?
  @ObservationIgnored private var isResumingDeferredReads = false
  @ObservationIgnored private var deferredReadWake: Task<Void, Never>?

  init(
    parsingClient: ReceiptParsingClient,
    storage: ReceiptStorageClient,
    access: ReadingAccess = .unlimited(),
    owner: @escaping @Sendable () async -> ReceiptOwner? = { nil },
    connectivity: ReceiptConnectivity = .live,
    connectionRetryLimit: Int = 3,
    connectionRetryDelay: Duration = .seconds(2)
  ) {
    self.parsingClient = parsingClient
    self.storage = storage
    self.access = access
    self.owner = owner
    self.connectivity = connectivity
    self.connectionRetryLimit = connectionRetryLimit
    self.connectionRetryDelay = connectionRetryDelay
  }

  /// The model's availability and quota. Reading it in a view body tracks changes.
  var modelStatus: ReceiptModelStatus {
    parsingClient.status()
  }

  func prewarm() {
    parsingClient.prewarm()
  }

  func showLimitIncrease() {
    parsingClient.showLimitIncrease()
  }

  func recognition(for id: UUID) -> ReceiptRecognition? {
    recognitions[id]
  }

  /// Whether a new read can reach the model right now.
  var canReadNow: Bool {
    switch modelStatus {
    case .available, .approachingLimit: true
    case .limitReached, .unavailable: false
    }
  }

  /// Starts reading `scan`. Pass the stored receipt to read an existing receipt again.
  @discardableResult
  func recognize(
    _ scan: ReceiptScan,
    backgroundStyle: ReceiptBackgroundStyle = .random(),
    replacing document: ReceiptDocument? = nil,
    isUserInitiated: Bool = true
  ) -> ReceiptRecognition {
    if let active = recognitions[scan.id] { return active }
    let recognition = ReceiptRecognition(
      scan: scan,
      backgroundStyle: document?.presentation.backgroundStyle ?? backgroundStyle,
      document: document,
      isUserInitiated: isUserInitiated)
    start(recognition)
    return recognition
  }

  /// Stops `recognition` and returns once it has finished, leaving the stored receipt as it was
  /// before the read.
  func cancel(_ recognition: ReceiptRecognition) async {
    recognition.task?.cancel()
    _ = await recognition.outcome
  }

  /// Reads stored receipts again whose reads stopped at the reading limit, once it has reset. Reads
  /// run one at a time, and the next reset is scheduled while the app stays open.
  func resumeDeferredReads(now: Date = Date()) async {
    guard !isResumingDeferredReads else { return }
    isResumingDeferredReads = true
    defer { isResumingDeferredReads = false }
    deferredReadWake?.cancel()
    deferredReadWake = nil

    guard let summaries = try? await storage.list() else { return }
    let deferred =
      summaries
      .filter { $0.deferredUntil != nil && recognitions[$0.id] == nil }
      .sorted { $0.capturedAt < $1.capturedAt }
    var pending: [Date] = []
    for summary in deferred {
      guard let deferredUntil = summary.deferredUntil else { continue }
      guard deferredUntil <= now, canReadNow else {
        pending.append(deferredUntil)
        continue
      }
      guard let recognition = await startDeferredRead(of: summary.id) else { continue }
      if case .failed = await recognition.outcome, !canReadNow {
        pending.append(now)
      }
    }
    scheduleDeferredReadWake(after: pending, now: Date())
  }

  private func startDeferredRead(of id: UUID) async -> ReceiptRecognition? {
    guard let document = try? await storage.load(id),
      document.recognition.status != .succeeded,
      document.recognition.deferredUntil != nil,
      let pages = try? await storage.loadPages(id),
      !pages.isEmpty
    else { return nil }
    let scan = ReceiptScan(
      id: document.id,
      pages: pages,
      capturedAt: document.scan.capturedAt,
      source: document.scan.source)
    return recognize(scan, replacing: document, isUserInitiated: false)
  }

  private func scheduleDeferredReadWake(after dates: [Date], now: Date) {
    guard let earliest = dates.min() else { return }
    var wake = earliest
    if case .limitReached(let resetDate, _) = modelStatus {
      guard let resetDate else { return }
      wake = max(wake, resetDate)
    }
    guard wake > now else { return }
    deferredReadWake = Task { [weak self] in
      try? await Task.sleep(for: .seconds(wake.timeIntervalSince(now)))
      guard !Task.isCancelled, let self else { return }
      // Resuming cancels any scheduled wake, which must not be this running one.
      deferredReadWake = nil
      await resumeDeferredReads()
    }
  }

  /// Starts a failed recognition again. A receipt that was already parsed is only saved again.
  func retry(_ failed: ReceiptRecognition) -> ReceiptRecognition {
    if let active = recognitions[failed.id] { return active }
    let recognition = ReceiptRecognition(
      scan: failed.scan,
      backgroundStyle: failed.backgroundStyle,
      document: failed.document,
      parsedReceipt: failed.parsedReceipt,
      isUserInitiated: true)
    start(recognition)
    return recognition
  }

  private func start(_ recognition: ReceiptRecognition) {
    recognitions[recognition.id] = recognition
    // A retry of a receipt that was already read only saves it, so it reads nothing.
    let readKey = recognition.parsedReceipt == nil ? Self.readKey(for: recognition) : nil
    // Admitting before the task starts keeps reads started together from sharing a free read.
    let isAdmitted = readKey.map { access.admit($0) } ?? true
    recognition.task = Task {
      let outcome: ReceiptRecognition.Outcome
      if let readKey, !isAdmitted, !(await access.admitAfterRefreshing(readKey)) {
        outcome = await storeUnread(recognition)
      } else {
        outcome = await run(recognition)
        if let readKey, Self.returnsFreeRead(after: outcome, of: recognition) {
          access.release(readKey)
        }
      }
      if recognitions[recognition.id] === recognition {
        recognitions[recognition.id] = nil
      }
      recognition.update(.finished)
      finishedCount += 1
      return outcome
    }

    if let page = recognition.scan.pages.first {
      Task.detached(priority: .userInitiated) {
        let thumbnail = ReceiptImageNormalizer.downscaled(page.image, maxPixelDimension: 360)
          .flatMap { ReceiptImageNormalizer.normalized($0, orientation: page.orientation) }
        await recognition.update(thumbnail: thumbnail)
      }
    }
  }

  /// The key a read is recorded under in the free read record. Every attempt at a receipt's first
  /// read shares a key, and reading it again after its pages change takes a new one.
  static func readKey(for recognition: ReceiptRecognition) -> String {
    var source = recognition.id.uuidString
    if recognition.isRescan {
      let pages = recognition.document?.scan.pages ?? []
      source += "/rescan" + pages.map { "/\($0.id.uuidString)" }.joined()
    }
    return SHA256.hash(data: Data(source.utf8)).prefix(16)
      .map { String(format: "%02x", $0) }.joined()
  }

  /// Whether a read that ended with `outcome` gives back its free read: it failed before the
  /// model answered and isn't waiting to read again, or it stopped before showing any items.
  private static func returnsFreeRead(
    after outcome: ReceiptRecognition.Outcome,
    of recognition: ReceiptRecognition
  ) -> Bool {
    switch outcome {
    case .recognized, .needsUnlock:
      false
    case .cancelled:
      !recognition.hasShownItems
    case .failed:
      recognition.parsedReceipt == nil && recognition.document?.recognition.deferredUntil == nil
    }
  }

  /// Keeps a receipt that can't be read without the purchase: a new scan is stored unread, and
  /// a deferred read stops waiting to start on its own.
  private func storeUnread(_ recognition: ReceiptRecognition) async -> ReceiptRecognition.Outcome {
    var document: ReceiptDocument
    do {
      document = try await storedDocument(for: recognition).value
    } catch {
      return .failed(message: error.localizedDescription, isRetryable: true)
    }
    if document.recognition.deferredUntil != nil, !recognition.isRescan {
      document.recognition.deferredUntil = nil
      document.updatedAt = max(Date(), document.updatedAt)
      if (try? await storage.save(document)) == nil {
        return .failed(message: "The receipt couldn’t be saved.", isRetryable: true)
      }
    }
    recognition.document = document
    return .needsUnlock
  }

  private func run(_ recognition: ReceiptRecognition) async -> ReceiptRecognition.Outcome {
    // A retry of a receipt that was already read only saves it, which needs no system progress.
    let activity = ReceiptReadActivity(
      continuesInBackground: recognition.isUserInitiated && recognition.parsedReceipt == nil,
      onExpiration: { [weak recognition] in recognition?.task?.cancel() })
    let outcome = await read(recognition, activity: activity)
    if case .recognized = outcome {
      activity.end(succeeded: true)
    } else {
      activity.end(succeeded: false)
    }
    return outcome
  }

  private func read(
    _ recognition: ReceiptRecognition,
    activity: ReceiptReadActivity
  ) async -> ReceiptRecognition.Outcome {
    let storedDocument = self.storedDocument(for: recognition)
    let attemptedAt = Date()

    let receipt: ParsedReceipt
    do {
      receipt = try await parsedReceipt(for: recognition, activity: activity)
    } catch {
      if let document = try? await storedDocument.value {
        recognition.document = document
      }
      // The model can report a stopped read as its own error, so cancellation is checked too.
      if error is CancellationError || Task.isCancelled { return .cancelled }
      return await recordFailure(error, of: recognition, attemptedAt: attemptedAt)
    }
    recognition.parsedReceipt = receipt

    let document: ReceiptDocument
    do {
      document = try await storedDocument.value
    } catch {
      return .failed(message: error.localizedDescription, isRetryable: true)
    }
    recognition.document = document

    recognition.update(.saving)
    let completed = completedDocument(
      from: document,
      receipt: receipt,
      owner: await owner(),
      attemptedAt: attemptedAt)
    // A read stopped after the model answered leaves the stored receipt as it was.
    guard !Task.isCancelled else { return .cancelled }
    do {
      try await storage.save(completed)
    } catch {
      return .failed(message: error.localizedDescription, isRetryable: true)
    }
    recognition.document = completed
    return .recognized(completed)
  }

  /// The receipt's stored document. A new scan is written to storage while the model reads it.
  private func storedDocument(
    for recognition: ReceiptRecognition
  ) -> Task<ReceiptDocument, any Error> {
    if let document = recognition.document {
      return Task { () async throws in document }
    }
    let storage = storage
    let scan = recognition.scan
    let backgroundStyle = recognition.backgroundStyle
    return Task { try await storage.create(scan, backgroundStyle) }
  }

  private func parsedReceipt(
    for recognition: ReceiptRecognition,
    activity: ReceiptReadActivity
  ) async throws -> ParsedReceipt {
    if let parsedReceipt = recognition.parsedReceipt { return parsedReceipt }
    if case .limitReached(let resetDate, _) = modelStatus {
      throw ReceiptParserError.quotaLimitReached(resetDate: resetDate)
    }
    var connectionRetries = 0
    while true {
      recognition.update(.reading)
      do {
        return try await parsingClient.stream(recognition.scan.pages) { preview in
          await MainActor.run {
            recognition.update(preview)
            activity.reportProgress(itemCount: preview.items.count)
          }
        }
      } catch let error as ReceiptParserError
        where error.isConnectionFailure && connectionRetries < connectionRetryLimit
      {
        connectionRetries += 1
        recognition.update(.waitingForConnection)
        recognition.resetPreview()
        await connectivity.waitUntilConnected()
        try Task.checkCancellation()
        try await Task.sleep(for: connectionRetryDelay * connectionRetries)
      }
    }
  }

  private func recordFailure(
    _ error: any Error,
    of recognition: ReceiptRecognition,
    attemptedAt: Date
  ) async -> ReceiptRecognition.Outcome {
    var message = error.localizedDescription
    // A rescan leaves the stored receipt untouched until a new recognition succeeds.
    if var document = recognition.document, !recognition.isRescan {
      let deferredUntil = Self.deferral(after: error, attemptedAt: attemptedAt)
      if let deferredUntil {
        message = DeferredReceiptRead.description(until: deferredUntil)
      }
      document.recognition.status = .failed
      document.recognition.failureMessage = message
      document.recognition.deferredUntil = deferredUntil
      document.recognition.contractVersion = ReceiptModelContract.version
      document.recognition.lastAttemptedAt = attemptedAt
      document.updatedAt = max(Date(), document.updatedAt)
      if (try? await storage.save(document)) != nil {
        recognition.document = document
      }
    }
    let isRetryable = (error as? ReceiptParserError)?.isRetryable ?? true
    return .failed(message: message, isRetryable: isRetryable)
  }

  /// When a read that failed with `error` should start again on its own, or `nil` when it
  /// shouldn't.
  private static func deferral(after error: any Error, attemptedAt: Date) -> Date? {
    switch error as? ReceiptParserError {
    case .quotaLimitReached(let resetDate), .rateLimited(let resetDate):
      max(resetDate ?? attemptedAt.addingTimeInterval(15 * 60), attemptedAt)
    default:
      nil
    }
  }

  private func completedDocument(
    from document: ReceiptDocument,
    receipt: ParsedReceipt,
    owner: ReceiptOwner?,
    attemptedAt: Date
  ) -> ReceiptDocument {
    let previousDraft =
      document.recognition.status == .succeeded ? try? ReceiptDraft(document: document) : nil
    let draft =
      previousDraft.map { ReceiptDraft(receipt: receipt, replacing: $0) }
      ?? ReceiptDraft(
        receipt: receipt,
        id: document.id,
        owner: owner,
        backgroundStyle: document.presentation.backgroundStyle)
    var completed = document.updating(from: draft)
    completed.recognition.contractVersion = ReceiptModelContract.version
    completed.recognition.lastAttemptedAt = attemptedAt
    completed.recognition.completedAt = Date()
    completed.recognition.pageIDs = document.scan.pages.map(\.id)
    return completed
  }
}
