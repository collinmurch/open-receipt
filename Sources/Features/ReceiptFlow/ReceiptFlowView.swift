import SwiftUI

struct ReceiptFlowView: View {
  @State private var model: ReceiptFlowModel
  @State private var motion: ReceiptBackgroundMotion
  @Environment(\.dismiss) private var dismiss
  @Environment(\.receiptParsingClient) private var parsingClient
  @Environment(\.receiptStorageClient) private var storage
  @Environment(\.peopleStorageClient) private var peopleStorage
  @Environment(\.receiptLibraryRefresh) private var refreshLibrary
  @Environment(\.scenePhase) private var scenePhase
  @Environment(ReceiptRecognitionCenter.self) private var recognitions

  init(input: ReceiptFlowInput) {
    let model = ReceiptFlowModel(input: input)
    _model = State(initialValue: model)
    _motion = State(
      initialValue: ReceiptBackgroundMotion(seed: input.id, isDrifting: model.isRecognizing))
  }

  var body: some View {
    content
      .background { background }
      .environment(\.receiptBackgroundMotion, motion)
      .sensoryFeedback(trigger: model.phase.kind) { oldKind, newKind in
        switch (oldKind, newKind) {
        case (.recognizing, .reviewing): .success
        // A read that stops at the reading limit waits rather than fails.
        case (.recognizing, .failed): model.failure?.isError == true ? .error : .warning
        case (_, .failed): model.failure?.isError == true ? .error : nil
        default: nil
        }
      }
      .onChange(of: model.isRecognizing) { _, isRecognizing in
        if isRecognizing {
          motion.drift()
        } else {
          motion.settle()
        }
      }
      .task(id: model.workID) {
        await model.performWork(using: recognitions, storage: storage, owner: owner)
      }
      .onChange(of: recognitions.recognition(for: model.receiptID) != nil) { _, isReading in
        if isReading { model.joinActiveRecognition(from: recognitions) }
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase != .active else { return }
        Task { _ = await model.flush(storage: storage) }
      }
      .onDisappear {
        Task {
          _ = await model.flush(storage: storage)
          refreshLibrary()
        }
      }
      .errorAlert(
        "Couldn’t Save Changes",
        message: Binding(
          get: { model.saveErrorDescription },
          set: { if $0 == nil { model.clearSaveError() } })
      ) {
        Button("Retry") {
          Task { _ = await model.flush(storage: storage) }
        }
        if model.reviewingDraft != nil {
          Button("Close Without Latest Changes", role: .destructive) {
            dismiss()
          }
        }
        Button("OK", role: .cancel) {}
      }
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .creating, .loading, .storing:
      ReceiptFlowPlaceholder()

    case .preparingRead, .rescanning:
      ReceiptFlowPlaceholder(title: "Preparing Pages")

    case .recognizing(let recognition):
      ReceiptRecognitionView(recognition: recognition, onEnterManually: stopReading)

    case .reviewing(let draft):
      ReceiptReviewView(
        draft: draft,
        showsSampleNotice: parsingClient.usesSampleData && !model.pages.pages.isEmpty,
        pages: pagesEditor,
        startsInEditing: model.startsInEditing,
        onFlush: { _ = await model.flush(storage: storage) }
      )
      .background {
        ReceiptAutosave(draft: draft) {
          await model.autosave(storage: storage)
        }
      }

    case .failed(let failure):
      ReceiptFailureView(
        failure: failure,
        backgroundStyle: model.backgroundStyle,
        onRetry: { model.retry(using: recognitions) },
        onEnterManually: enterManually)
    }
  }

  /// One background behind every phase and page of the receipt, so switching between them only
  /// changes what sits on top of it.
  @ViewBuilder
  private var background: some View {
    if let style = model.backgroundStyle {
      ReceiptInkWashBackground(style: style)
    } else {
      Color(.systemGroupedBackground).ignoresSafeArea()
    }
  }

  /// The contact new receipts start with as the person using the app.
  private var owner: @Sendable () async -> ReceiptOwner? {
    let peopleStorage = peopleStorage
    return { try? await peopleStorage.owner() }
  }

  private func enterManually() {
    Task { await model.enterManually(storage: storage, owner: owner) }
  }

  private func stopReading() {
    Task {
      await model.stopReadingAndEnterManually(
        using: recognitions, storage: storage, owner: owner)
    }
  }

  private var pagesEditor: ReceiptPagesEditor {
    ReceiptPagesEditor(
      pages: model.pages.pages,
      needsRescan: model.pages.needsRescan,
      add: { try await model.addPages($0, storage: storage) },
      delete: { try await model.deletePage($0, storage: storage) },
      reorder: { try await model.reorderPages($0, storage: storage) },
      rescan: model.rescan)
  }
}

/// A receipt that couldn't be read or hasn't been read yet. Reading again waits while the reading
/// limit is reached, and the receipt can always be entered by hand.
private struct ReceiptFailureView: View {
  let failure: ReceiptFlowModel.Failure
  /// The receipt's colors, which tint its buttons as they do on the rest of the receipt.
  let backgroundStyle: ReceiptBackgroundStyle?
  let onRetry: () -> Void
  let onEnterManually: () -> Void
  @State private var isUnlockPresented = false
  @Environment(\.colorScheme) private var colorScheme
  @Environment(ReceiptRecognitionCenter.self) private var recognitions
  @Environment(ReadingAccess.self) private var access

  var body: some View {
    Group {
      if isLocked {
        locked
      } else {
        unread
      }
    }
    .tint(backgroundStyle?.accentColor(for: colorScheme))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .unlimitedReadingSheet(isPresented: $isUnlockPresented, onUnlock: onRetry)
  }

  /// Reading this receipt needs the purchase: a read was refused, or an unread receipt is opened
  /// with every free read used.
  private var isLocked: Bool {
    guard !access.isUnlocked else { return false }
    return failure.needsUnlock || (failure.isUnread && access.freeReadsLeft == 0)
  }

  private var unread: some View {
    ContentUnavailableView {
      Label(failure.title, systemImage: failure.systemImage)
    } description: {
      Text(failure.description)
    } actions: {
      VStack(spacing: 12) {
        if let retry = failure.retry {
          Button(retryTitle(retry), action: onRetry)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(backgroundStyle?.prominentColor)
            .disabled(retry.readsReceipt && !recognitions.canReadNow)
          if retry.readsReceipt, let readingNote, readingNote != failure.description {
            Text(readingNote)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        manualEntryButton
      }
    }
  }

  private var locked: some View {
    ContentUnavailableView {
      Label("Free Reads Used", systemImage: "lock.fill")
        .symbolRenderingMode(.hierarchical)
    } description: {
      Text(lockedDescription)
    } actions: {
      VStack(spacing: 12) {
        Button("Unlock Unlimited Reading") { isUnlockPresented = true }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .tint(backgroundStyle?.prominentColor)
        manualEntryButton
        Text("One-time purchase. No subscription.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
      }
    }
  }

  private var lockedDescription: String {
    let reason =
      failure.needsUnlock ? failure.description : ReceiptFlowModel.Failure.unlockDescription
    return "You’ve used all \(ReadingAccess.freeReadLimit) free reads. \(reason)"
  }

  @ViewBuilder
  private var manualEntryButton: some View {
    if failure.allowsManualEntry {
      Button(failure.manualEntryTitle, action: onEnterManually)
        .buttonStyle(.glass)
    }
  }

  private func retryTitle(_ retry: ReceiptFlowModel.Failure.Retry) -> String {
    switch retry {
    case .read: "Read Receipt"
    case .create, .load, .store, .recognize: "Try Again"
    }
  }

  private var readingNote: String? {
    switch recognitions.modelStatus {
    case .limitReached(let resetDate, _):
      resetDate.map { "Reading is available again \(DeferredReceiptRead.resumption(at: $0))." }
        ?? "Reading is available again later."
    case .unavailable(let reason):
      reason
    case .available, .approachingLimit:
      freeReadsNote
    }
  }

  private var freeReadsNote: String? {
    guard !access.isUnlocked, !failure.needsUnlock else { return nil }
    return access.freeReadsLeft == 0
      ? "Reading this receipt needs unlimited reading."
      : "\(access.freeReadsLeftDescription)."
  }
}

/// Saves a draft shortly after each durable change. It is its own view so edits redraw only it,
/// not the receipt around it.
private struct ReceiptAutosave: View {
  let draft: ReceiptDraft
  let save: () async -> Void

  var body: some View {
    Color.clear
      .task(id: draft.persistenceRevision) { await save() }
  }
}

/// Shown while the receipt loads, with a spinner only when loading is slow enough to notice.
private struct ReceiptFlowPlaceholder: View {
  var title: String?
  @State private var showsProgress = false

  var body: some View {
    VStack(spacing: 14) {
      if showsProgress {
        ProgressView()
        if let title {
          Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task {
      try? await Task.sleep(for: .milliseconds(400))
      withAnimation(.smooth) { showsProgress = true }
    }
  }
}
