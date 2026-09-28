import SwiftUI

struct ReceiptFlowView: View {
  @State private var model: ReceiptFlowModel
  @State private var motion: ReceiptBackgroundMotion
  private let startsInEditing: Bool
  private let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.receiptParsingClient) private var parsingClient
  @Environment(\.receiptStorageClient) private var storage
  @Environment(\.peopleStorageClient) private var peopleStorage
  @Environment(\.receiptLibraryRefresh) private var refreshLibrary
  @Environment(\.scenePhase) private var scenePhase
  @Environment(ReceiptRecognitionCenter.self) private var recognitions

  init(input: ReceiptFlowInput, onClose: (() -> Void)? = nil) {
    self.onClose = onClose
    let model = ReceiptFlowModel(input: input)
    _model = State(initialValue: model)
    _motion = State(
      initialValue: ReceiptBackgroundMotion(seed: input.id, isDrifting: model.isRecognizing))
    if case .create = input.source {
      startsInEditing = true
    } else {
      startsInEditing = false
    }
  }

  var body: some View {
    content
      .toolbar {
        if onClose != nil, model.reviewingDraft == nil {
          ToolbarItem(placement: .topBarLeading) {
            Button("Close", systemImage: "xmark", action: closeReceipt)
              .labelStyle(.iconOnly)
          }
        }
      }
      .environment(\.receiptBackgroundMotion, motion)
      .animation(.smooth(duration: 0.45), value: model.phase.kind)
      .sensoryFeedback(trigger: model.phase.kind) { oldKind, newKind in
        switch (oldKind, newKind) {
        case (.recognizing, .reviewing): .success
        case (_, .failed): .error
        default: nil
        }
      }
      .errorHaptic(model.saveErrorDescription)
      .onChange(of: model.isRecognizing) { _, isRecognizing in
        if isRecognizing {
          motion.drift()
        } else {
          motion.settle()
        }
      }
      .task(id: model.workID) {
        let peopleStorage = peopleStorage
        await model.performWork(using: recognitions, storage: storage) {
          try? await peopleStorage.owner()
        }
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
      .alert(
        "Couldn’t Save Changes",
        isPresented: Binding(
          get: { model.saveErrorDescription != nil },
          set: { if !$0 { model.clearSaveError() } })
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
      } message: {
        Text(model.saveErrorDescription ?? "The receipt could not be saved.")
      }
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .creating, .loading:
      ReceiptFlowPlaceholder(style: model.backgroundStyle)

    case .rescanning:
      ReceiptFlowPlaceholder(style: model.backgroundStyle, title: "Preparing Pages")

    case .recognizing(let recognition):
      ReceiptRecognitionView(recognition: recognition)

    case .reviewing(let draft):
      ReceiptReviewView(
        draft: draft,
        showsSampleNotice: parsingClient.usesSampleData && !model.pages.pages.isEmpty,
        pages: pagesEditor,
        startsInEditing: startsInEditing,
        onClose: onClose.map { _ in closeReceipt },
        onFlush: { _ = await model.flush(storage: storage) }
      )
      .background {
        ReceiptAutosave(draft: draft) {
          await model.autosave(storage: storage)
        }
      }

    case .failed(let failure):
      ContentUnavailableView {
        Label("Couldn’t Read Receipt", systemImage: "exclamationmark.triangle")
      } description: {
        Text(failure.description)
      } actions: {
        VStack(spacing: 12) {
          if failure.retry != nil {
            Button("Try Again") { model.retry(using: recognitions) }
              .buttonStyle(.glassProminent)
          }
          if failure.allowsManualEntry {
            Button("Enter Manually", action: enterManually)
              .buttonStyle(.glass)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        if let style = model.backgroundStyle {
          ReceiptInkWashBackground(style: style)
        }
      }
    }
  }

  private func enterManually() {
    let peopleStorage = peopleStorage
    Task {
      await model.enterManually(storage: storage) {
        try? await peopleStorage.owner()
      }
    }
  }

  /// Saves pending edits before closing, so a failed save can be retried from the receipt.
  private func closeReceipt() {
    Task {
      if await model.flush(storage: storage) {
        onClose?()
      }
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

/// The receipt's background while it loads, with a spinner only when loading is slow enough to
/// notice.
private struct ReceiptFlowPlaceholder: View {
  let style: ReceiptBackgroundStyle?
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
    .background {
      if let style {
        ReceiptInkWashBackground(style: style)
      } else {
        Color(.systemGroupedBackground).ignoresSafeArea()
      }
    }
    .task {
      try? await Task.sleep(for: .milliseconds(400))
      withAnimation(.smooth) { showsProgress = true }
    }
  }
}
