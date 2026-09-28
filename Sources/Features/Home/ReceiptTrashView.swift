import SwiftUI

struct ReceiptTrashView: View {
  let deletedReceipts: [DeletedReceiptSummary]
  let onBack: () -> Void
  let onRestore: (DeletedReceiptSummary) -> Void
  let onDelete: (DeletedReceiptSummary) -> Void
  let onEmpty: () -> Void
  @State private var isEmptyConfirmationPresented = false
  @State private var haptic = HapticEvent()

  var body: some View {
    VStack(spacing: 0) {
      trashHeader
      trashList
    }
    .haptics(haptic)
  }

  private func restore(_ deletedReceipt: DeletedReceiptSummary) {
    haptic.play(.success)
    onRestore(deletedReceipt)
  }

  private func delete(_ deletedReceipt: DeletedReceiptSummary) {
    haptic.play(.removal)
    onDelete(deletedReceipt)
  }

  private func empty() {
    haptic.play(.removal)
    onEmpty()
  }

  private var trashList: some View {
    List {
      if deletedReceipts.isEmpty {
        ContentUnavailableView(
          "No Deleted Receipts",
          systemImage: "trash",
          description: Text("Deleted receipts appear here for 30 days.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .historyRowStyle()
      } else {
        Section {
          ForEach(deletedReceipts) { deletedReceipt in
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
            .libraryRowStyle()
          }
        }

        Section {
          Text("Permanently deleted after 30 days")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .historyRowStyle()
        }
      }
    }
    .listStyle(.plain)
    .contentMargins(.top, 6, for: .scrollContent)
    .scrollContentBackground(.hidden)
  }

  private var trashHeader: some View {
    HStack {
      Button("Back", systemImage: "chevron.backward") {
        onBack()
      }
      .labelStyle(.iconOnly)
      .font(.body.weight(.semibold))
      .frame(width: 44, height: 44)
      .buttonStyle(.plain)
      .glassEffect(.regular.interactive(), in: .circle)

      Spacer()

      Button("Empty", role: .destructive) {
        isEmptyConfirmationPresented = true
      }
      .font(.body.weight(.semibold))
      .padding(.horizontal, 16)
      .frame(height: 44)
      .buttonStyle(.plain)
      .foregroundStyle(.red)
      .glassEffect(.regular.interactive(), in: .capsule)
      .disabled(deletedReceipts.isEmpty)
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
    .overlay {
      Text("Recently Deleted")
        .font(.headline)
        .lineLimit(1)
    }
    .padding(.horizontal, 16)
    .padding(.top, 18)
    .padding(.bottom, 14)
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
