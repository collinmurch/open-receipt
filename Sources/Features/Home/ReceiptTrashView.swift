import SwiftUI

struct ReceiptTrashView: View {
  @State private var isEmptyConfirmationPresented = false
  @State private var haptic = HapticEvent()
  @Environment(ReceiptLibraryModel.self) private var library

  var body: some View {
    List {
      if library.deletedReceipts.isEmpty {
        ContentUnavailableView(
          "No Deleted Receipts",
          systemImage: "trash",
          description: Text("Deleted receipts appear here for 30 days.")
        )
        .listRowBackground(Color.clear)
      } else {
        Section {
          ForEach(library.deletedReceipts) { deletedReceipt in
            ReceiptTrashRow(
              deletedReceipt: deletedReceipt,
              onRestore: { restore(deletedReceipt) }
            )
            .contextMenu {
              Button("Restore", systemImage: "arrow.uturn.backward") {
                restore(deletedReceipt)
              }
              Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                delete(deletedReceipt)
              }
            }
            .swipeActions(edge: .leading) {
              Button("Restore", systemImage: "arrow.uturn.backward") {
                restore(deletedReceipt)
              }
              .tint(.blue)
            }
            .swipeActions(edge: .trailing) {
              Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                delete(deletedReceipt)
              }
            }
          }
        } footer: {
          Text("Receipts are permanently deleted after 30 days.")
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background { ReceiptLibraryBackground() }
    .navigationTitle("Recently Deleted")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Empty", role: .destructive) {
          isEmptyConfirmationPresented = true
        }
        .disabled(library.deletedReceipts.isEmpty)
        .confirmationDialog(
          "Delete all receipts now?",
          isPresented: $isEmptyConfirmationPresented,
          titleVisibility: .visible
        ) {
          Button("Delete All", role: .destructive, action: empty)
        } message: {
          Text("You cannot restore these receipts after you delete them.")
        }
      }
    }
    .haptics(haptic)
  }

  private func restore(_ deletedReceipt: DeletedReceiptSummary) {
    haptic.play(.success)
    Task { await library.restore(deletedReceipt) }
  }

  private func delete(_ deletedReceipt: DeletedReceiptSummary) {
    haptic.play(.removal)
    Task { await library.permanentlyDelete(deletedReceipt) }
  }

  private func empty() {
    haptic.play(.removal)
    Task { await library.emptyTrash() }
  }
}

private struct ReceiptTrashRow: View {
  let deletedReceipt: DeletedReceiptSummary
  let onRestore: () -> Void
  @State private var isRestorePopoverPresented = false

  var body: some View {
    Button {
      isRestorePopoverPresented = true
    } label: {
      ReceiptLibraryRow(receipt: deletedReceipt.receipt)
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isRestorePopoverPresented, arrowEdge: .bottom) {
      Button("Restore Receipt", systemImage: "arrow.uturn.backward") {
        isRestorePopoverPresented = false
        onRestore()
      }
      .font(.body.weight(.semibold))
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
      .presentationCompactAdaptation(.popover)
    }
  }
}
