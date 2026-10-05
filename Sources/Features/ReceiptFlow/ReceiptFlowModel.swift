import Foundation
import Observation

struct ReceiptFlowInput: Identifiable, Hashable {
  enum Source {
    case create
    case storedReceipt
    case recognition(ReceiptRecognition)
    /// A new scan to store without reading, because the model can't read it.
    case unreadScan(ReceiptScan)
  }

  /// The receipt identifier.
  let id: UUID
  let source: Source
  /// The receipt's colors, when they are known before it loads.
  let backgroundStyle: ReceiptBackgroundStyle?
  /// The stored receipt, when it was loaded before the screen opened, so the receipt shows on the
  /// first frame instead of loading during the transition.
  var preloadedDocument: ReceiptDocument?

  static func create(
    id: UUID = UUID(),
    backgroundStyle: ReceiptBackgroundStyle = .random()
  ) -> ReceiptFlowInput {
    ReceiptFlowInput(id: id, source: .create, backgroundStyle: backgroundStyle)
  }

  static func storedReceipt(
    _ id: UUID,
    backgroundStyle: ReceiptBackgroundStyle? = nil,
    document: ReceiptDocument? = nil
  ) -> ReceiptFlowInput {
    ReceiptFlowInput(
      id: id,
      source: .storedReceipt,
      backgroundStyle: backgroundStyle,
      preloadedDocument: document)
  }

  @MainActor
  static func recognition(_ recognition: ReceiptRecognition) -> ReceiptFlowInput {
    ReceiptFlowInput(
      id: recognition.id,
      source: .recognition(recognition),
      backgroundStyle: recognition.backgroundStyle)
  }

  /// Opens a new scan. It is read right away, or stored unread when the model is unavailable so
  /// its values can be entered by hand.
  @MainActor
  static func scan(
    _ scan: ReceiptScan,
    recognitions: ReceiptRecognitionCenter
  ) -> ReceiptFlowInput {
    guard case .unavailable = recognitions.modelStatus else {
      return .recognition(recognitions.recognize(scan))
    }
    return ReceiptFlowInput(id: scan.id, source: .unreadScan(scan), backgroundStyle: .random())
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
      case store(ReceiptScan)
      case recognize(ReceiptRecognition)
      /// Reads a stored scan that hasn't been read.
      case read(UUID)

      /// Whether retrying sends the scan to the model.
      var readsReceipt: Bool {
        switch self {
        case .recognize, .read: true
        case .create, .load, .store: false
        }
      }
    }

    var title = "Couldn’t Read Receipt"
    var systemImage = "exclamationmark.triangle"
    /// Whether something went wrong, as opposed to a receipt that is waiting to be read.
    var isError = true
    let description: String
    let retry: Retry?
    /// Whether the stored scan can be kept and its values entered by hand.
    var allowsManualEntry = false
    var manualEntryTitle = "Enter Manually"
    /// Whether reading needs the one-time purchase, which then retries.
    var needsUnlock = false
    /// Whether the receipt is stored but has never been read, and isn't waiting to be.
    var isUnread = false

    /// Why a stored receipt can't be read until reading is unlocked.
    static let unlockDescription =
      "This receipt is saved. Unlock unlimited reading to read it, or enter its items yourself."
  }

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
  @ObservationIgnored private(set) var lastSavedRevision = 0
  @ObservationIgnored let receiptID: UUID

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
    guard case .failed = phase, let active = recognitions.recognition(for: receiptID) else {
      return
    }
    phase = .recognizing(active)
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
    case .needsUnlock:
      phase = .failed(
        Failure(
          title: "Free Reads Used",
          systemImage: "lock",
          isError: false,
          description: recognition.isRescan
            ? "Unlock unlimited reading to read this receipt again."
            : Failure.unlockDescription,
          retry: .recognize(recognition),
          allowsManualEntry: true,
          manualEntryTitle: recognition.isRescan ? "Back to Receipt" : "Enter Manually",
          needsUnlock: true))
    case .recognized(let document):
      do {
        try review(document)
      } catch {
        phase = .failed(Failure(description: error.localizedDescription, retry: .load(document.id)))
      }
    case .failed(let message, let isRetryable) where recognition.isRescan:
      phase = .failed(
        Failure(
          title: "Couldn’t Rescan Receipt",
          description: message,
          retry: isRetryable ? .recognize(recognition) : nil,
          allowsManualEntry: true,
          manualEntryTitle: "Back to Receipt"))
    case .failed(let message, let isRetryable):
      let isDeferred = recognition.document?.recognition.deferredUntil != nil
      phase = .failed(
        Failure(
          title: isDeferred ? "Waiting to Read" : "Couldn’t Read Receipt",
          systemImage: isDeferred ? "hourglass" : "exclamationmark.triangle",
          isError: !isDeferred,
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
    recognitions.prewarm()
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
    open(document)
  }

  /// Shows a loaded receipt: its review when it was read, or its unread state.
  private func open(_ document: ReceiptDocument) {
    backgroundStyle = document.presentation.backgroundStyle
    guard document.recognition.status == .succeeded else {
      phase = .failed(Self.unreadFailure(for: document))
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
    if let active = recognitions.recognition(for: id) {
      phase = .recognizing(active)
      return
    }
    recognitions.prewarm()
    do {
      let document = try await storage.load(id)
      let pages = try await storage.loadPages(id)
      guard !Task.isCancelled else { return }
      let scan = ReceiptScan(
        id: document.id,
        pages: pages,
        capturedAt: document.scan.capturedAt,
        source: document.scan.source)
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

  private static func unreadFailure(for document: ReceiptDocument) -> Failure {
    let recognition = document.recognition
    if let deferredUntil = recognition.deferredUntil {
      return Failure(
        title: "Waiting to Read",
        systemImage: "hourglass",
        isError: false,
        description: DeferredReceiptRead.description(until: deferredUntil),
        retry: .read(document.id),
        allowsManualEntry: true)
    }
    if recognition.status == .failed {
      return Failure(
        description: recognition.failureMessage ?? "The receipt couldn’t be read.",
        retry: .read(document.id),
        allowsManualEntry: true)
    }
    return Failure(
      title: "Receipt Not Read",
      systemImage: "doc.text.viewfinder",
      isError: false,
      description: "Read this receipt to fill in its items and totals, or enter them yourself.",
      retry: .read(document.id),
      allowsManualEntry: true,
      isUnread: true)
  }
}
