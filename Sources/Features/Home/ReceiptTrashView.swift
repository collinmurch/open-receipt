import SwiftUI

/// Receipts deleted in the last 30 days. Selecting acts on the chosen receipts, or on all of them
/// when none are chosen.
struct ReceiptTrashView: View {
  @State private var editMode = EditMode.inactive
  @State private var selection: Set<DeletedReceiptSummary.ID> = []
  @State private var isDeleteConfirmationPresented = false
  @State private var haptic = HapticEvent()
  @Environment(ReceiptLibraryModel.self) private var library

  var body: some View {
    List(selection: $selection) {
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
            ReceiptLibraryRow(receipt: deletedReceipt.receipt)
              .contextMenu {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                  restore([deletedReceipt])
                }
                Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                  delete([deletedReceipt])
                }
              }
              .swipeActions(edge: .leading) {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                  restore([deletedReceipt])
                }
                .tint(.blue)
              }
              .swipeActions(edge: .trailing) {
                Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                  delete([deletedReceipt])
                }
              }
          }
        } footer: {
          Text("Receipts are permanently deleted after 30 days.")
        }
      }
    }
    .environment(\.editMode, $editMode)
    .scrollContentBackground(.hidden)
    .background { ReceiptLibraryBackground() }
    .navigationTitle("Recently Deleted")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { trashToolbar }
    .confirmationDialog(
      deleteConfirmationTitle,
      isPresented: $isDeleteConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button(deleteTitle, role: .destructive) { delete(targetedReceipts) }
    } message: {
      Text("You cannot restore these receipts after you delete them.")
    }
    .onChange(of: library.deletedReceipts.isEmpty) { _, isEmpty in
      if isEmpty { setSelecting(false) }
    }
    .haptics(haptic)
  }

  @ToolbarContentBuilder
  private var trashToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button(isSelecting ? "Cancel" : "Select") { setSelecting(!isSelecting) }
        .disabled(library.deletedReceipts.isEmpty)
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
          isDeleteConfirmationPresented = true
        }
      }
    }
  }

  private var isSelecting: Bool {
    editMode.isEditing
  }

  /// The selected receipts, or every deleted receipt when none are selected.
  private var targetedReceipts: [DeletedReceiptSummary] {
    guard !selection.isEmpty else { return library.deletedReceipts }
    return library.deletedReceipts.filter { selection.contains($0.id) }
  }

  private var deleteTitle: String {
    selection.isEmpty ? "Delete All" : "Delete"
  }

  private var deleteConfirmationTitle: String {
    selection.isEmpty
      ? "Delete all receipts now?"
      : "Delete \(String(inflecting: "^[\(selection.count) receipt](inflect: true)")) now?"
  }

  private func setSelecting(_ isSelecting: Bool) {
    selection = []
    withAnimation(.smooth(duration: 0.3)) {
      editMode = isSelecting ? .active : .inactive
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

  private func delete(_ deletedReceipts: [DeletedReceiptSummary]) {
    haptic.play(.removal)
    let deletesAll = deletedReceipts.count == library.deletedReceipts.count
    setSelecting(false)
    Task {
      if deletesAll {
        await library.emptyTrash()
      } else {
        for deletedReceipt in deletedReceipts {
          await library.permanentlyDelete(deletedReceipt)
        }
      }
    }
  }
}
