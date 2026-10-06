import SwiftUI

/// Receipts deleted in the last 30 days. Tapping a receipt offers to restore and open it, and long
/// pressing lifts it into focus with its actions. Selecting acts on the chosen receipts, or on all
/// of them when none are chosen. Selection is the list's own, so dragging along the checkmarks or
/// panning with two fingers selects a run of receipts.
struct ReceiptTrashView: View {
  let onOpen: (HomeRoute) -> Void
  @State private var editMode: EditMode = .inactive
  @State private var selection: Set<DeletedReceiptSummary.ID> = []
  /// Receipts waiting on confirmation before they're deleted for good.
  @State private var pendingDeletion: [DeletedReceiptSummary]?
  @State private var restorePrompt: DeletedReceiptSummary?
  @State private var focusedID: DeletedReceiptSummary.ID?
  @State private var focusedRowFrame: CGRect?
  @State private var isFocusedRowPressed = false
  @State private var haptic = HapticEvent()
  @Environment(ReceiptLibraryModel.self) private var library
  @Environment(\.receiptStorageClient) private var storage

  var body: some View {
    List(selection: $selection) {
      if !library.deletedReceipts.isEmpty {
        Section {
          ForEach(library.deletedReceipts) { deletedReceipt in
            row(for: deletedReceipt)
          }
        } footer: {
          Text("Receipts are permanently deleted after 30 days.")
        }
      }
    }
    .environment(\.editMode, $editMode)
    .scrollContentBackground(.hidden)
    .background { AppBackground() }
    .overlay {
      if library.deletedReceipts.isEmpty {
        ContentUnavailableView(
          "No Deleted Receipts",
          systemImage: "trash",
          description: Text("Deleted receipts appear here for 30 days.")
        )
      }
    }
    .overlay { trashFocus }
    .navigationTitle("Recently Deleted")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(isFocusing || isSelecting)
    .toolbar { trashToolbar }
    .confirmationDialog(
      deleteConfirmationTitle,
      isPresented: $pendingDeletion.isPresent,
      titleVisibility: .visible,
      presenting: pendingDeletion
    ) { deletedReceipts in
      Button(deletesAll(deletedReceipts) ? "Delete All" : "Delete", role: .destructive) {
        delete(deletedReceipts)
      }
    } message: { deletedReceipts in
      Text(
        deletedReceipts.count == 1
          ? "You can’t restore this receipt after you delete it."
          : "You can’t restore these receipts after you delete them.")
    }
    .alert(
      "Restore Receipt?",
      isPresented: $restorePrompt.isPresent,
      presenting: restorePrompt
    ) { deletedReceipt in
      Button("Restore") { restoreAndOpen(deletedReceipt) }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("This receipt is in Recently Deleted. Restore it to open it.")
    }
    .onChange(of: library.deletedReceipts) { _, deletedReceipts in
      let ids = Set(deletedReceipts.map(\.id))
      selection.formIntersection(ids)
      if deletedReceipts.isEmpty { setSelecting(false) }
      if let focusedID, !ids.contains(focusedID) { endFocus() }
    }
    .haptics(haptic)
  }

  @ToolbarContentBuilder
  private var trashToolbar: some ToolbarContent {
    if !isFocusing {
      ToolbarItem(placement: .topBarTrailing) {
        Button(isSelecting ? "Cancel" : "Select") { setSelecting(!isSelecting) }
          .disabled(library.deletedReceipts.isEmpty)
      }
    }

    if isSelecting {
      ToolbarItem(placement: .bottomBar) {
        Button(selection.isEmpty ? "Restore All" : "Restore") {
          restore(targetedReceipts)
        }
      }
      ToolbarSpacer(.flexible, placement: .bottomBar)
      ToolbarItem(placement: .bottomBar) {
        Button(deleteTitle, role: .destructive) {
          pendingDeletion = targetedReceipts
        }
      }
    }
  }

  private func row(for deletedReceipt: DeletedReceiptSummary) -> some View {
    let isFocused = deletedReceipt.id == focusedID
    return ReceiptTrashRow(
      deletedReceipt: deletedReceipt,
      isSelecting: isSelecting,
      isFocused: isFocused,
      isLiftedOut: isFocused && focusedRowFrame != nil,
      onTap: { tap(deletedReceipt) },
      onFocus: { focus(deletedReceipt, isPressed: $0) },
      onFocusedFrameChange: { focusedRowFrame = $0 }
    )
    .swipeActions(edge: .leading) {
      if !isSelecting {
        Button("Restore", systemImage: "arrow.uturn.backward") {
          restore([deletedReceipt])
        }
        .tint(.blue)
      }
    }
    .swipeActions(edge: .trailing) {
      if !isSelecting {
        // Not destructive, which would remove the row before the deletion is confirmed.
        Button("Delete Permanently", systemImage: "trash") {
          pendingDeletion = [deletedReceipt]
        }
        .tint(.red)
      }
    }
  }

  @ViewBuilder
  private var trashFocus: some View {
    if let focusedID, let focusedRowFrame,
      let deletedReceipt = library.deletedReceipts.first(where: { $0.id == focusedID })
    {
      ReceiptRowFocusView(
        row: ReceiptLibraryRow(
          receipt: deletedReceipt.receipt, expiresAt: deletedReceipt.expiresAt),
        rowFrame: focusedRowFrame,
        startsPressed: isFocusedRowPressed,
        primaryAction: .init(title: "Restore", systemImage: "arrow.uturn.backward") {
          restore([deletedReceipt])
        },
        primaryTint: .blue,
        deleteAction: .init(title: "Delete Permanently", systemImage: "trash") {
          pendingDeletion = [deletedReceipt]
        },
        onDismiss: endFocus
      )
      // The focus view animates its own arrival, starting over the row it copies.
      .transition(.identity)
    }
  }

  private var isFocusing: Bool { focusedID != nil }

  private var isSelecting: Bool { editMode.isEditing }

  /// The selected receipts, or every deleted receipt when none are selected.
  private var targetedReceipts: [DeletedReceiptSummary] {
    guard !selection.isEmpty else { return library.deletedReceipts }
    return library.deletedReceipts.filter { selection.contains($0.id) }
  }

  private var deleteTitle: String {
    selection.isEmpty ? "Delete All" : "Delete"
  }

  private var deleteConfirmationTitle: String {
    guard let pendingDeletion else { return "" }
    if pendingDeletion.count == 1 { return "Delete this receipt now?" }
    if deletesAll(pendingDeletion) { return "Delete all receipts now?" }
    return "Delete \(String(inflecting: "^[\(pendingDeletion.count) receipt](inflect: true)")) now?"
  }

  private func deletesAll(_ deletedReceipts: [DeletedReceiptSummary]) -> Bool {
    deletedReceipts.count > 1 && deletedReceipts.count == library.deletedReceipts.count
  }

  private func setSelecting(_ isSelecting: Bool) {
    // Leaving clears the selection only once the list is out of edit mode; clearing both at once
    // leaves the list showing its checkmarks.
    if isSelecting { selection = [] }
    withAnimation(.smooth(duration: 0.3)) {
      editMode = isSelecting ? .active : .inactive
    } completion: {
      if !editMode.isEditing { selection = [] }
    }
  }

  private func tap(_ deletedReceipt: DeletedReceiptSummary) {
    guard !isSelecting, !deletedReceipt.receipt.isUnavailable else { return }
    restorePrompt = deletedReceipt
  }

  private func focus(_ deletedReceipt: DeletedReceiptSummary, isPressed: Bool) {
    guard !isFocusing, !isSelecting else { return }
    haptic.play(.lift)
    isFocusedRowPressed = isPressed
    withAnimation(.settle) {
      focusedID = deletedReceipt.id
    }
  }

  private func endFocus() {
    withAnimation(.settle) {
      focusedID = nil
      focusedRowFrame = nil
    }
  }

  private func restore(_ deletedReceipts: [DeletedReceiptSummary]) {
    haptic.play(.success)
    setSelecting(false)
    Task {
      for deletedReceipt in deletedReceipts {
        await library.restore(deletedReceipt)
      }
    }
  }

  /// Restores `deletedReceipt`, then opens it once its document has loaded.
  private func restoreAndOpen(_ deletedReceipt: DeletedReceiptSummary) {
    haptic.play(.success)
    Task {
      guard await library.restore(deletedReceipt) else { return }
      let receipt = deletedReceipt.receipt
      let document = try? await storage.load(receipt.id)
      onOpen(
        .receipt(
          .storedReceipt(
            receipt.id, backgroundStyle: receipt.backgroundStyle, document: document)))
    }
  }

  private func delete(_ deletedReceipts: [DeletedReceiptSummary]) {
    haptic.play(.removal)
    let isEmptyingTrash = deletedReceipts.count == library.deletedReceipts.count
    setSelecting(false)
    Task {
      if isEmptyingTrash {
        await library.emptyTrash()
      } else {
        for deletedReceipt in deletedReceipts {
          await library.permanentlyDelete(deletedReceipt)
        }
      }
    }
  }
}

/// A deleted receipt in the list. A long press lifts it into focus. While selecting, the gesture
/// steps aside so the list handles taps and drags.
private struct ReceiptTrashRow: View {
  let deletedReceipt: DeletedReceiptSummary
  let isSelecting: Bool
  let isFocused: Bool
  let isLiftedOut: Bool
  let onTap: () -> Void
  let onFocus: (_ isPressed: Bool) -> Void
  let onFocusedFrameChange: (CGRect) -> Void

  var body: some View {
    ReceiptLibraryRow(receipt: deletedReceipt.receipt, expiresAt: deletedReceipt.expiresAt)
      .liftableRow(
        isFocused: isFocused,
        isLiftedOut: isLiftedOut,
        isEnabled: !isSelecting,
        onTap: onTap,
        onLongPress: { onFocus(true) },
        onFocusedFrameChange: onFocusedFrameChange
      )
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(isSelecting ? [] : .isButton)
      .accessibilityActions {
        if !isSelecting {
          Button("Restore and Open", action: onTap)
          Button("Restore or Delete") { onFocus(false) }
        }
      }
  }
}
