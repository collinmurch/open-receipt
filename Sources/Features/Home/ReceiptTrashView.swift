import SwiftUI

/// Receipts deleted in the last 30 days. Tapping a receipt offers to restore and open it, and long
/// pressing lifts it into focus with its actions. Selecting acts on the chosen receipts, or on all
/// of them when none are chosen.
struct ReceiptTrashView: View {
  let onOpen: (HomeRoute) -> Void
  @State private var isSelecting = false
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
    List {
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
    .scrollContentBackground(.hidden)
    .background { ReceiptLibraryBackground() }
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
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } }
      ),
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
      isPresented: Binding(
        get: { restorePrompt != nil },
        set: { if !$0 { restorePrompt = nil } }
      ),
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
      isSelected: selection.contains(deletedReceipt.id),
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
    selection = []
    withAnimation(.smooth(duration: 0.3)) {
      self.isSelecting = isSelecting
    }
  }

  private func tap(_ deletedReceipt: DeletedReceiptSummary) {
    guard isSelecting else {
      if !deletedReceipt.receipt.isUnavailable { restorePrompt = deletedReceipt }
      return
    }
    withAnimation(.selectionChange) {
      if selection.contains(deletedReceipt.id) {
        selection.remove(deletedReceipt.id)
      } else {
        selection.insert(deletedReceipt.id)
      }
    }
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

/// A deleted receipt in the list. Taps and long presses are one gesture rather than a button or a
/// context menu, as receipt items are, so a long press lifts the receipt into focus.
private struct ReceiptTrashRow: View {
  let deletedReceipt: DeletedReceiptSummary
  let isSelecting: Bool
  let isSelected: Bool
  let isFocused: Bool
  let isLiftedOut: Bool
  let onTap: () -> Void
  let onFocus: (_ isPressed: Bool) -> Void
  let onFocusedFrameChange: (CGRect) -> Void

  @State private var isPressed = false

  var body: some View {
    HStack(spacing: 12) {
      if isSelecting {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.title2)
          .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
          .contentTransition(.symbolEffect(.replace))
          .transition(.move(edge: .leading).combined(with: .opacity))
      }

      ReceiptLibraryRow(receipt: deletedReceipt.receipt, expiresAt: deletedReceipt.expiresAt)
        .onGeometryChange(for: CGRect?.self) { proxy in
          isFocused ? proxy.frame(in: .global) : nil
        } action: { frame in
          if let frame { onFocusedFrameChange(frame) }
        }
    }
    .pressScale(isPressed && !isSelecting)
    .opacity(isLiftedOut ? 0 : 1)
    .transaction(value: isLiftedOut) { $0.animation = nil }
    .contentShape(.rect)
    .gesture(
      ReceiptRowPressGesture(
        onPressingChanged: { isPressed = $0 },
        onTap: onTap,
        onLongPress: isSelecting ? onTap : { onFocus(true) }
      )
    )
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelecting && isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityAction(.default, onTap)
    .accessibilityHint(isSelecting ? Text("") : Text("Restore and open this receipt"))
    .accessibilityActions {
      if !isSelecting {
        Button("Restore or Delete") { onFocus(false) }
      }
    }
  }
}
