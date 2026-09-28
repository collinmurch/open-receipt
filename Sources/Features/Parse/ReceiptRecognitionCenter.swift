import Observation
import UIKit

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
  @ObservationIgnored private let connectivity: ReceiptConnectivity
  @ObservationIgnored private let connectionRetryLimit: Int
  @ObservationIgnored private let connectionRetryDelay: Duration
  @ObservationIgnored private let owner: @Sendable () async -> ReceiptOwner?

  init(
    parsingClient: ReceiptParsingClient,
    storage: ReceiptStorageClient,
    owner: @escaping @Sendable () async -> ReceiptOwner? = { nil },
    connectivity: ReceiptConnectivity = .live,
    connectionRetryLimit: Int = 3,
    connectionRetryDelay: Duration = .seconds(2)
  ) {
    self.parsingClient = parsingClient
    self.storage = storage
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

  /// Starts reading `scan`. Pass the stored receipt to read an existing receipt again.
  @discardableResult
  func recognize(
    _ scan: ReceiptScan,
    backgroundStyle: ReceiptBackgroundStyle = .random(),
    replacing document: ReceiptDocument? = nil
  ) -> ReceiptRecognition {
    if let active = recognitions[scan.id] { return active }
    let recognition = ReceiptRecognition(
      scan: scan,
      backgroundStyle: document?.presentation.backgroundStyle ?? backgroundStyle,
      document: document)
    start(recognition)
    return recognition
  }

  /// Starts a failed recognition again. A receipt that was already parsed is only saved again.
  func retry(_ failed: ReceiptRecognition) -> ReceiptRecognition {
    if let active = recognitions[failed.id] { return active }
    let recognition = ReceiptRecognition(
      scan: failed.scan,
      backgroundStyle: failed.backgroundStyle,
      document: failed.document,
      parsedReceipt: failed.parsedReceipt)
    start(recognition)
    return recognition
  }

  private func start(_ recognition: ReceiptRecognition) {
    recognitions[recognition.id] = recognition
    recognition.task = Task {
      let outcome = await run(recognition)
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

  private func run(_ recognition: ReceiptRecognition) async -> ReceiptRecognition.Outcome {
    let activity = BackgroundActivity(name: "Read receipt")
    defer { activity.end() }

    let creation = createDocumentIfNeeded(for: recognition)
    let attemptedAt = Date()

    let receipt: ParsedReceipt
    do {
      receipt = try await parsedReceipt(for: recognition)
    } catch {
      if let creation, let document = try? await creation.value {
        recognition.document = document
      }
      return await recordFailure(error, of: recognition, attemptedAt: attemptedAt)
    }
    recognition.parsedReceipt = receipt

    let document: ReceiptDocument
    do {
      if let creation {
        recognition.document = try await creation.value
      }
      guard let stored = recognition.document else { throw ReceiptStorageError.emptyScan }
      document = stored
    } catch {
      return .failed(message: error.localizedDescription, isRetryable: true)
    }

    recognition.update(.saving)
    let completed = completedDocument(
      from: document,
      receipt: receipt,
      owner: await owner(),
      attemptedAt: attemptedAt)
    do {
      try await storage.save(completed)
    } catch {
      return .failed(message: error.localizedDescription, isRetryable: true)
    }
    recognition.document = completed
    return .recognized(completed)
  }

  private func createDocumentIfNeeded(
    for recognition: ReceiptRecognition
  ) -> Task<ReceiptDocument, any Error>? {
    guard recognition.document == nil else { return nil }
    let storage = storage
    let scan = recognition.scan
    let backgroundStyle = recognition.backgroundStyle
    return Task { try await storage.create(scan, backgroundStyle) }
  }

  private func parsedReceipt(for recognition: ReceiptRecognition) async throws -> ParsedReceipt {
    if let parsedReceipt = recognition.parsedReceipt { return parsedReceipt }
    var connectionRetries = 0
    while true {
      recognition.update(.reading)
      do {
        return try await parsingClient.stream(recognition.scan.pages) { preview in
          await recognition.update(preview)
        }
      } catch let error as ReceiptParserError
        where error.isConnectionFailure && connectionRetries < connectionRetryLimit
      {
        connectionRetries += 1
        recognition.update(.waitingForConnection)
        recognition.resetPreview()
        await connectivity.waitUntilConnected()
        try await Task.sleep(for: connectionRetryDelay * connectionRetries)
      }
    }
  }

  private func recordFailure(
    _ error: any Error,
    of recognition: ReceiptRecognition,
    attemptedAt: Date
  ) async -> ReceiptRecognition.Outcome {
    let message = error.localizedDescription
    // A rescan leaves the stored receipt untouched until a new recognition succeeds.
    if var document = recognition.document, !recognition.isRescan {
      document.recognition.status = .failed
      document.recognition.failureMessage = message
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
    let validationWarnings = Set(ReceiptValidator.warnings(for: receipt))
    completed.recognition.warnings = receipt.warnings.filter { !validationWarnings.contains($0) }
    return completed
  }
}

/// Keeps the app running briefly after it moves to the background, so a read can finish.
@MainActor
private final class BackgroundActivity {
  private var identifier = UIBackgroundTaskIdentifier.invalid

  init(name: String) {
    identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      self?.end()
    }
  }

  func end() {
    guard identifier != .invalid else { return }
    UIApplication.shared.endBackgroundTask(identifier)
    identifier = .invalid
  }
}
