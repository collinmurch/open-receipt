import SwiftUI

/// Where the library goes once the drawer has closed.
enum ReceiptLibraryDestination {
  case scanner
  case receipt(ReceiptFlowInput)
}

struct ReceiptLibraryView: View {
  /// Tall enough to show the newest receipt and a sliver of the next.
  private static let collapsedHeight: CGFloat = 228

  let onHistoryDismiss: () -> Void
  let onOpen: (ReceiptLibraryDestination) -> Void
  @Binding private var isHistoryPresented: Bool
  @State private var selectedDetent = PresentationDetent.height(Self.collapsedHeight)
  @State private var searchText = ""
  @State private var pendingDestination: ReceiptLibraryDestination?
  @State private var isTrashPresented = false
  @State private var trashSwipeOffset: CGFloat = 0
  @State private var deletionCount = 0
  @Environment(ReceiptLibraryModel.self) private var library
  @Environment(ReceiptRecognitionCenter.self) private var recognitions
  @Environment(\.scenePhase) private var scenePhase

  init(
    isHistoryPresented: Binding<Bool>,
    onHistoryDismiss: @escaping () -> Void,
    onOpen: @escaping (ReceiptLibraryDestination) -> Void
  ) {
    _isHistoryPresented = isHistoryPresented
    self.onHistoryDismiss = onHistoryDismiss
    self.onOpen = onOpen
  }

  var body: some View {
    ZStack {
      ReceiptLibraryBackground()

      GeometryReader { geometry in
        NewReceiptView(
          onScan: presentScanner,
          onRecognize: recognize,
          onCreate: { prepareToOpen(.receipt(.create())) }
        )
        .padding(.horizontal, 24)
        .padding(.bottom, Self.collapsedHeight)
        .frame(maxWidth: .infinity, maxHeight: geometry.size.height)
      }
    }
    .sheet(isPresented: $isHistoryPresented, onDismiss: finishHistoryDismissal) {
      historyDrawer
    }
    .task { await library.load() }
    .onChange(of: recognitions.finishedCount) {
      Task { await library.load() }
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      Task { await library.refreshTrashIfNeeded() }
    }
    .errorHaptic(library.errorDescription)
    .alert(
      "Couldn’t Update Receipts",
      isPresented: Binding(
        get: { library.errorDescription != nil },
        set: { if !$0 { library.errorDescription = nil } })
    ) {
      Button("Retry") { Task { await library.load() } }
      Button("OK", role: .cancel) {}
    } message: {
      Text(library.errorDescription ?? "The receipt library could not be updated.")
    }
  }

  private var historyDrawer: some View {
    GeometryReader { geometry in
      ZStack {
        if !isTrashPresented || trashSwipeOffset > 0 {
          ReceiptHistorySheet(
            receipts: displayedReceipts,
            isLoading: library.isLoading,
            searchText: $searchText,
            onOpen: open,
            onDelete: delete,
            onOpenRecentlyDeleted: openTrash
          )
          .offset(x: isTrashPresented ? trashSwipeOffset - geometry.size.width : 0)
          .transition(.move(edge: .leading))
        }

        if isTrashPresented {
          ReceiptTrashView(
            deletedReceipts: library.deletedReceipts,
            onBack: closeTrash,
            onRestore: { deletedReceipt in
              Task { await library.restore(deletedReceipt) }
            },
            onDelete: { deletedReceipt in
              Task { await library.permanentlyDelete(deletedReceipt) }
            },
            onEmpty: { Task { await library.emptyTrash() } }
          )
          .offset(x: trashSwipeOffset)
          .transition(.move(edge: .trailing))
          .gesture(
            EdgeSwipeBackGesture(
              onChanged: { trashSwipeOffset = min($0, geometry.size.width) },
              onEnded: { translation, velocity in
                finishTrashSwipe(
                  translation: translation, velocity: velocity, width: geometry.size.width)
              }
            )
          )
        }
      }
    }
    .clipped()
    .animation(.smooth(duration: 0.35), value: isTrashPresented)
    .presentationDetents([.height(Self.collapsedHeight), .large], selection: $selectedDetent)
    .presentationDragIndicator(.visible)
    .presentationContentInteraction(.resizes)
    .presentationBackgroundInteraction(.enabled(upThrough: .height(Self.collapsedHeight)))
    .interactiveDismissDisabled()
    .sensoryFeedback(.removal, trigger: deletionCount)
  }

  /// Library receipts, led by any new receipt being read that storage has not listed yet.
  private var displayedReceipts: [ReceiptSummary] {
    let storedIDs = Set(library.receipts.map(\.id))
    let reading = recognitions.recognitions.values
      .filter { !storedIDs.contains($0.id) && !$0.isRescan }
      .sorted { $0.capturedAt > $1.capturedAt }
      .map { recognition in
        ReceiptSummary(
          id: recognition.id,
          updatedAt: recognition.capturedAt,
          capturedAt: recognition.capturedAt,
          backgroundStyle: recognition.backgroundStyle,
          recognitionStatus: .pending,
          merchantName: nil,
          localDate: nil,
          total: nil,
          currency: nil,
          isUnavailable: false,
          unavailableDescription: nil)
      }
    return reading + library.receipts
  }

  private func presentScanner() {
    recognitions.prewarm()
    prepareToOpen(.scanner)
  }

  /// Reading starts now, while the drawer closes, rather than after the receipt opens.
  private func recognize(_ scan: ReceiptScan) {
    prepareToOpen(.receipt(.recognition(recognitions.recognize(scan))))
  }

  private func open(_ receipt: ReceiptSummary, recognition: ReceiptRecognition?) {
    guard !receipt.isUnavailable else { return }
    let input =
      recognition.map(ReceiptFlowInput.recognition)
      ?? .storedReceipt(receipt.id, backgroundStyle: receipt.backgroundStyle)
    prepareToOpen(.receipt(input))
  }

  private func prepareToOpen(_ destination: ReceiptLibraryDestination) {
    pendingDestination = destination
    isHistoryPresented = false
  }

  private func delete(_ receipt: ReceiptSummary) {
    guard recognitions.recognition(for: receipt.id) == nil else { return }
    deletionCount += 1
    Task { await library.delete(receipt) }
  }

  private func finishHistoryDismissal() {
    isTrashPresented = false
    trashSwipeOffset = 0
    if let pendingDestination {
      self.pendingDestination = nil
      onOpen(pendingDestination)
    }
    onHistoryDismiss()
  }

  private func openTrash() {
    guard selectedDetent != .large else {
      isTrashPresented = true
      return
    }
    withAnimation(.smooth(duration: 0.35), completionCriteria: .removed) {
      selectedDetent = .large
    } completion: {
      isTrashPresented = true
    }
  }

  private func closeTrash() {
    withAnimation(.smooth(duration: 0.35)) {
      isTrashPresented = false
    }
  }

  private func finishTrashSwipe(translation: CGFloat, velocity: CGFloat, width: CGFloat) {
    let projectedTranslation = translation + velocity * 0.2
    guard projectedTranslation > width / 2 else {
      withAnimation(.smooth(duration: 0.25)) {
        trashSwipeOffset = 0
      }
      return
    }
    withAnimation(.smooth(duration: 0.25), completionCriteria: .removed) {
      trashSwipeOffset = width
    } completion: {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        isTrashPresented = false
        trashSwipeOffset = 0
      }
    }
  }
}
