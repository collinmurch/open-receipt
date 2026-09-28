import Foundation
import Observation

struct ReceiptFlowInput: Identifiable, Hashable {
  enum Source {
    case create
    case storedReceipt
    case recognition(ReceiptRecognition)
  }

  /// The receipt identifier.
  let id: UUID
  let source: Source
  /// The receipt's colors, when they are known before it loads.
  let backgroundStyle: ReceiptBackgroundStyle?

  static func create(
    id: UUID = UUID(),
    backgroundStyle: ReceiptBackgroundStyle = .random()
  ) -> ReceiptFlowInput {
    ReceiptFlowInput(id: id, source: .create, backgroundStyle: backgroundStyle)
  }

  static func storedReceipt(
    _ id: UUID,
    backgroundStyle: ReceiptBackgroundStyle? = nil
  ) -> ReceiptFlowInput {
    ReceiptFlowInput(id: id, source: .storedReceipt, backgroundStyle: backgroundStyle)
  }

  @MainActor
  static func recognition(_ recognition: ReceiptRecognition) -> ReceiptFlowInput {
    ReceiptFlowInput(
      id: recognition.id,
      source: .recognition(recognition),
      backgroundStyle: recognition.backgroundStyle)
  }

  static func == (lhs: ReceiptFlowInput, rhs: ReceiptFlowInput) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

/// A receipt's stored pages and whether its values predate them.
struct ReceiptPagesState: Equatable {
  var pages: [ReceiptDocument.Page]
  var needsRescan: Bool

  static let empty = ReceiptPagesState(pages: [], needsRescan: false)

  init(pages: [ReceiptDocument.Page], needsRescan: Bool) {
    self.pages = pages
    self.needsRescan = needsRescan
  }

  init(document: ReceiptDocument) {
    self.init(pages: document.scan.pages, needsRescan: document.needsRescan)
  }
}

@MainActor
@Observable
final class ReceiptFlowModel {
  struct Failure {
    enum Retry {
      case create(UUID)
      case load(UUID)
      case recognize(ReceiptRecognition)
    }

    let description: String
    let retry: Retry?
    /// Whether the stored scan can be kept and its values entered by hand.
    var allowsManualEntry = false
  }

  enum Phase {
    case creating(UUID)
    case loading(UUID)
    case recognizing(ReceiptRecognition)
    case reviewing(ReceiptDraft)
    case rescanning(ReceiptDraft)
    case failed(Failure)

    enum Kind: Equatable {
      case creating
      case loading
      case recognizing
      case reviewing
      case rescanning
      case failed
    }

    var kind: Kind {
      switch self {
      case .creating: .creating
      case .loading: .loading
      case .recognizing: .recognizing
      case .reviewing: .reviewing
      case .rescanning: .rescanning
      case .failed: .failed
      }
    }
  }

  private(set) var phase: Phase
  private(set) var pages = ReceiptPagesState.empty
  private(set) var backgroundStyle: ReceiptBackgroundStyle?
  private(set) var saveErrorDescription: String?
  /// The last stored snapshot. Saves replace it without redrawing the receipt.
  @ObservationIgnored private(set) var document: ReceiptDocument?
  @ObservationIgnored private(set) var lastSavedRevision = 0
  @ObservationIgnored private let receiptID: UUID

  init(input: ReceiptFlowInput) {
    receiptID = input.id
    backgroundStyle = input.backgroundStyle
    switch input.source {
    case .create:
      phase = .creating(input.id)
    case .storedReceipt:
      phase = .loading(input.id)
    case .recognition(let recognition):
      phase = .recognizing(recognition)
    }
  }

  var workID: String? {
    switch phase {
    case .creating(let id):
      "create-\(id.uuidString)"
    case .loading(let id):
      "load-\(id.uuidString)"
    case .recognizing(let recognition):
      "recognize-\(ObjectIdentifier(recognition).hashValue)"
    case .rescanning(let draft):
      "rescan-\(draft.id.uuidString)"
    case .reviewing, .failed:
      nil
    }
  }

  /// Whether the model is reading the receipt, or preparing to.
  var isRecognizing: Bool {
    switch phase {
    case .recognizing, .rescanning: true
    default: false
    }
  }

  var reviewingDraft: ReceiptDraft? {
    guard case .reviewing(let draft) = phase else { return nil }
    return draft
  }

  func addPages(_ pages: [ReceiptPage], storage: ReceiptStorageClient) async throws {
    guard case .reviewing = phase else { return }
    adoptScan(from: try await storage.addPages(receiptID, pages))
  }

  func deletePage(_ pageID: ReceiptDocument.Page.ID, storage: ReceiptStorageClient) async throws {
    guard case .reviewing = phase else { return }
    adoptScan(from: try await storage.deletePage(receiptID, pageID))
  }

  func reorderPages(
    _ pageIDs: [ReceiptDocument.Page.ID],
    storage: ReceiptStorageClient
  ) async throws {
    guard case .reviewing = phase else { return }
    adoptScan(from: try await storage.reorderPages(receiptID, pageIDs))
  }

  func rescan() {
    guard case .reviewing(let draft) = phase, pages.needsRescan else { return }
    phase = .rescanning(draft)
  }

  func performWork(
    using recognitions: ReceiptRecognitionCenter,
    storage: ReceiptStorageClient,
    owner: @Sendable () async -> ReceiptOwner? = { nil }
  ) async {
    switch phase {
    case .creating(let id):
      await createBlank(id: id, storage: storage, owner: owner)
    case .loading(let id):
      await load(id: id, recognitions: recognitions, storage: storage)
    case .recognizing(let recognition):
      await finish(recognition)
    case .rescanning(let draft):
      await prepareRescan(of: draft, recognitions: recognitions, storage: storage)
    case .reviewing, .failed:
      break
    }
  }

  func retry(using recognitions: ReceiptRecognitionCenter) {
    guard case .failed(let failure) = phase, let retry = failure.retry else { return }
    switch retry {
    case .create(let id):
      phase = .creating(id)
    case .load(let id):
      phase = .loading(id)
    case .recognize(let recognition):
      phase = .recognizing(recognitions.retry(recognition))
    }
  }

  /// Keeps a scan that couldn't be read and opens it for entering values by hand. A failed rescan
  /// returns to the values that were already stored.
  func enterManually(
    storage: ReceiptStorageClient,
    owner: @Sendable () async -> ReceiptOwner? = { nil }
  ) async {
    guard case .failed(let failure) = phase, failure.allowsManualEntry else { return }
    do {
      var document = try await storage.load(receiptID)
      if document.recognition.status != .succeeded {
        let draft = ReceiptDraft(
          receipt: ParsedReceipt(),
          id: document.id,
          owner: await owner(),
          backgroundStyle: document.presentation.backgroundStyle)
        document = document.updating(from: draft)
        try await storage.save(document)
      }
      guard case .failed = phase else { return }
      try review(document)
    } catch {
      phase = .failed(
        Failure(
          description: error.localizedDescription,
          retry: failure.retry,
          allowsManualEntry: true))
    }
  }

  func autosave(storage: ReceiptStorageClient) async {
    do {
      try await Task.sleep(for: .milliseconds(300))
      try Task.checkCancellation()
      try await saveNow(storage: storage)
    } catch is CancellationError {
      return
    } catch {
      saveErrorDescription = error.localizedDescription
    }
  }

  func saveNow(storage: ReceiptStorageClient) async throws {
    guard case .reviewing(let draft) = phase,
      let document,
      draft.persistenceRevision != lastSavedRevision
    else { return }
    let revision = draft.persistenceRevision
    let snapshot = document.updating(from: draft)
    try await storage.save(snapshot)
    guard case .reviewing(let currentDraft) = phase, currentDraft === draft else { return }
    self.document = snapshot
    lastSavedRevision = revision
    clearSaveError()
  }

  func flush(storage: ReceiptStorageClient) async -> Bool {
    do {
      try await saveNow(storage: storage)
      return true
    } catch {
      saveErrorDescription = error.localizedDescription
      return false
    }
  }

  func clearSaveError() {
    guard saveErrorDescription != nil else { return }
    saveErrorDescription = nil
  }

  private func adoptScan(from updated: ReceiptDocument) {
    guard case .reviewing = phase, var document, document.id == updated.id else { return }
    document.scan = updated.scan
    self.document = document
    updatePages(from: document)
  }

  private func review(_ document: ReceiptDocument) throws {
    let draft = try ReceiptDraft(document: document)
    self.document = document
    lastSavedRevision = draft.persistenceRevision
    if backgroundStyle != draft.backgroundStyle {
      backgroundStyle = draft.backgroundStyle
    }
    updatePages(from: document)
    phase = .reviewing(draft)
  }

  private func updatePages(from document: ReceiptDocument) {
    let pages = ReceiptPagesState(document: document)
    if self.pages != pages {
      self.pages = pages
    }
  }

  private func finish(_ recognition: ReceiptRecognition) async {
    let outcome = await recognition.outcome
    guard !Task.isCancelled else { return }
    switch outcome {
    case .recognized(let document):
      do {
        try review(document)
      } catch {
        phase = .failed(Failure(description: error.localizedDescription, retry: .load(document.id)))
      }
    case .failed(let message, let isRetryable):
      phase = .failed(
        Failure(
          description: message,
          retry: isRetryable ? .recognize(recognition) : nil,
          allowsManualEntry: true))
    }
  }

  private func prepareRescan(
    of draft: ReceiptDraft,
    recognitions: ReceiptRecognitionCenter,
    storage: ReceiptStorageClient
  ) async {
    do {
      let snapshot = try await storage.load(receiptID).updating(from: draft)
      try await storage.save(snapshot)
      let pages = try await storage.loadPages(receiptID)
      guard !Task.isCancelled else { return }
      let scan = ReceiptScan(
        id: snapshot.id,
        pages: pages,
        capturedAt: snapshot.scan.capturedAt,
        source: snapshot.scan.source)
      phase = .recognizing(recognitions.recognize(scan, replacing: snapshot))
    } catch is CancellationError {
      return
    } catch {
      phase = .failed(Failure(description: error.localizedDescription, retry: .load(receiptID)))
    }
  }

  private func createBlank(
    id: UUID,
    storage: ReceiptStorageClient,
    owner: @Sendable () async -> ReceiptOwner?
  ) async {
    do {
      let document = try await storage.createBlank(id, backgroundStyle ?? .random())
      let owner = await owner()
      guard !Task.isCancelled else { return }
      try review(document)
      if let owner, case .reviewing(let draft) = phase {
        draft.setOwner(owner)
      }
    } catch is CancellationError {
      return
    } catch {
      phase = .failed(Failure(description: error.localizedDescription, retry: .create(id)))
    }
  }

  private func load(
    id: UUID,
    recognitions: ReceiptRecognitionCenter,
    storage: ReceiptStorageClient
  ) async {
    if let active = recognitions.recognition(for: id) {
      phase = .recognizing(active)
      return
    }

    let document: ReceiptDocument
    do {
      document = try await storage.load(id)
    } catch is CancellationError {
      return
    } catch {
      phase = .failed(Failure(description: error.localizedDescription, retry: .load(id)))
      return
    }

    guard !Task.isCancelled else { return }
    if document.recognition.status == .succeeded {
      do {
        try review(document)
      } catch {
        phase = .failed(Failure(description: error.localizedDescription, retry: nil))
      }
      return
    }

    do {
      let pages = try await storage.loadPages(id)
      guard !Task.isCancelled else { return }
      backgroundStyle = document.presentation.backgroundStyle
      let scan = ReceiptScan(
        id: document.id,
        pages: pages,
        capturedAt: document.scan.capturedAt,
        source: document.scan.source)
      phase = .recognizing(recognitions.recognize(scan, replacing: document))
    } catch is CancellationError {
      return
    } catch {
      phase = .failed(Failure(description: error.localizedDescription, retry: .load(id)))
    }
  }
}
