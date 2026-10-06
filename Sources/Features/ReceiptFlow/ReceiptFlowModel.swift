import Foundation
import Observation

/// A receipt's stored pages and whether its values predate them.
struct ReceiptPagesState: Equatable {
  var pages: [ReceiptDocument.Page]
  var needsRescan: Bool

  static let empty = ReceiptPagesState(pages: [], needsRescan: false)
}

extension ReceiptPagesState {
  init(document: ReceiptDocument) {
    self.init(pages: document.scan.pages, needsRescan: document.needsRescan)
  }
}

@MainActor
@Observable
final class ReceiptFlowModel {
  enum Phase {
    case creating(UUID)
    case loading(UUID)
    case storing(ReceiptScan)
    case preparingRead(UUID)
    case recognizing(ReceiptRecognition)
    case reviewing(ReceiptDraft)
    case rescanning(ReceiptDraft)
    case failed(Failure)

    enum Kind: Equatable {
      case creating
      case loading
      case storing
      case preparingRead
      case recognizing
      case reviewing
      case rescanning
      case failed
    }

    var kind: Kind {
      switch self {
      case .creating: .creating
      case .loading: .loading
      case .storing: .storing
      case .preparingRead: .preparingRead
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
  /// Whether the review opens ready to edit, for a receipt whose values are entered by hand.
  @ObservationIgnored private(set) var startsInEditing = false
  /// The last stored snapshot. Saves replace it without redrawing the receipt.
  @ObservationIgnored private(set) var document: ReceiptDocument?
  @ObservationIgnored private var lastSavedRevision = 0
  let receiptID: UUID

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
    case .unreadScan(let scan):
      phase = .storing(scan)
    }
    if let document = input.preloadedDocument, document.id == input.id {
      open(document)
    }
  }

  /// The work the current phase needs done, which restarts whenever it changes.
  enum Work: Hashable {
    case create(UUID)
    case load(UUID)
    case store(UUID)
    case read(UUID)
    case recognize(ObjectIdentifier)
    case rescan(UUID)
  }

  var workID: Work? {
    switch phase {
    case .creating(let id): .create(id)
    case .loading(let id): .load(id)
    case .storing(let scan): .store(scan.id)
    case .preparingRead(let id): .read(id)
    case .recognizing(let recognition): .recognize(ObjectIdentifier(recognition))
    case .rescanning(let draft): .rescan(draft.id)
    case .reviewing, .failed: nil
    }
  }

  /// Whether the model is reading the receipt, or preparing to.
  var isRecognizing: Bool {
    switch phase {
    case .preparingRead, .recognizing, .rescanning: true
    default: false
    }
  }

  var failure: Failure? {
    guard case .failed(let failure) = phase else { return nil }
    return failure
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
    case .storing(let scan):
      await storeUnread(scan, storage: storage)
    case .preparingRead(let id):
      await prepareRead(id: id, recognitions: recognitions, storage: storage)
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
    case .store(let scan):
      phase = .storing(scan)
    case .recognize(let recognition):
      phase = .recognizing(recognitions.retry(recognition))
    case .read(let id):
      phase = .preparingRead(id)
    }
  }

  /// Follows a read of this receipt that started elsewhere, such as a read deferred until the
  /// reading limit reset.
  func joinActiveRecognition(from recognitions: ReceiptRecognitionCenter) {
    guard case .failed = phase else { return }
    joinActiveRecognition(of: receiptID, from: recognitions)
  }

  /// Follows the read of `id` under way, if there is one, returning whether there was.
  @discardableResult
  private func joinActiveRecognition(
    of id: UUID,
    from recognitions: ReceiptRecognitionCenter
  ) -> Bool {
    guard let active = recognitions.recognition(for: id) else { return false }
    phase = .recognizing(active)
    return true
  }

  /// Keeps a scan that couldn't be read and opens it for entering values by hand. A failed rescan
  /// returns to the values that were already stored.
  func enterManually(
    storage: ReceiptStorageClient,
    owner: @Sendable () async -> ReceiptOwner? = { nil }
  ) async {
    guard case .failed(let failure) = phase, failure.allowsManualEntry else { return }
    await openForManualEntry(retry: failure.retry, storage: storage, owner: owner)
  }

  /// Stops the read in progress and opens the receipt for entering values by hand. A stopped
  /// rescan returns to the values that were already stored.
  func stopReadingAndEnterManually(
    using recognitions: ReceiptRecognitionCenter,
    storage: ReceiptStorageClient,
    owner: @Sendable () async -> ReceiptOwner? = { nil }
  ) async {
    guard case .recognizing(let recognition) = phase else { return }
    let retry: Failure.Retry = recognition.isRescan ? .load(receiptID) : .read(receiptID)
    await recognitions.cancel(recognition)
    await openForManualEntry(retry: retry, storage: storage, owner: owner)
  }

  private func openForManualEntry(
    retry: Failure.Retry?,
    storage: ReceiptStorageClient,
    owner: @Sendable () async -> ReceiptOwner?
  ) async {
    let workID = workID
    do {
      var document = try await storage.load(receiptID)
      let isUnread = document.recognition.status != .succeeded
      if isUnread {
        let draft = ReceiptDraft(
          receipt: ParsedReceipt(),
          id: document.id,
          owner: await owner(),
          backgroundStyle: document.presentation.backgroundStyle)
        document = document.updating(from: draft)
        try await storage.save(document)
      }
      guard self.workID == workID else { return }
      try review(document, startsInEditing: isUnread)
    } catch {
      phase = .failed(
        Failure(
          description: error.localizedDescription,
          retry: retry,
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

  private func saveNow(storage: ReceiptStorageClient) async throws {
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

  @discardableResult
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

  private func review(_ document: ReceiptDocument, startsInEditing: Bool = false) throws {
    let draft = try ReceiptDraft(document: document)
    self.startsInEditing = startsInEditing
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
    case .cancelled:
      return
    case .needsUnlock where recognition.isRescan:
      phase = .failed(.rescanNotRead(retry: .recognize(recognition)))
    case .needsUnlock:
      // The scan was stored unread, so it opens the way any unread receipt does.
      guard let document = recognition.document else { return }
      phase = .failed(.unread(document))
    case .recognized(let document):
      do {
        try review(document)
      } catch {
        phase = .failed(Failure(description: error.localizedDescription, retry: .load(document.id)))
      }
    case .failed(let message, let isRetryable) where recognition.isRescan:
      phase = .failed(
        .rescanFailed(message, retry: isRetryable ? .recognize(recognition) : nil))
    case .failed(let message, let isRetryable):
      phase = .failed(
        .readFailed(
          message,
          retry: isRetryable ? .recognize(recognition) : nil,
          isDeferred: recognition.document?.recognition.deferredUntil != nil))
    }
  }

  private func prepareRescan(
    of draft: ReceiptDraft,
    recognitions: ReceiptRecognitionCenter,
    storage: ReceiptStorageClient
  ) async {
    recognitions.prewarm()
    do {
      let snapshot = try await storage.load(receiptID).updating(from: draft)
      try await storage.save(snapshot)
      let pages = try await storage.loadPages(receiptID)
      guard !Task.isCancelled else { return }
      let scan = ReceiptScan(document: snapshot, pages: pages)
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
      try review(document, startsInEditing: true)
      if let owner, case .reviewing(let draft) = phase {
        draft.setOwner(owner)
      }
    } catch is CancellationError {
      return
    } catch {
      phase = .failed(Failure(description: error.localizedDescription, retry: .create(id)))
    }
  }

  private func storeUnread(_ scan: ReceiptScan, storage: ReceiptStorageClient) async {
    do {
      let document = try await storage.create(scan, backgroundStyle ?? .random())
      guard !Task.isCancelled else { return }
      open(document)
    } catch is CancellationError {
      return
    } catch {
      phase = .failed(Failure(description: error.localizedDescription, retry: .store(scan)))
    }
  }

  private func load(
    id: UUID,
    recognitions: ReceiptRecognitionCenter,
    storage: ReceiptStorageClient
  ) async {
    if joinActiveRecognition(of: id, from: recognitions) { return }

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
    open(document)
  }

  /// Shows a loaded receipt: its review when it was read, or its unread state.
  private func open(_ document: ReceiptDocument) {
    backgroundStyle = document.presentation.backgroundStyle
    guard document.recognition.status == .succeeded else {
      phase = .failed(.unread(document))
      return
    }
    do {
      try review(document)
    } catch {
      phase = .failed(Failure(description: error.localizedDescription, retry: nil))
    }
  }

  private func prepareRead(
    id: UUID,
    recognitions: ReceiptRecognitionCenter,
    storage: ReceiptStorageClient
  ) async {
    if joinActiveRecognition(of: id, from: recognitions) { return }
    recognitions.prewarm()
    do {
      let document = try await storage.load(id)
      let pages = try await storage.loadPages(id)
      guard !Task.isCancelled else { return }
      let scan = ReceiptScan(document: document, pages: pages)
      phase = .recognizing(recognitions.recognize(scan, replacing: document))
    } catch is CancellationError {
      return
    } catch {
      phase = .failed(
        Failure(
          description: error.localizedDescription,
          retry: .read(id),
          allowsManualEntry: true))
    }
  }
}
