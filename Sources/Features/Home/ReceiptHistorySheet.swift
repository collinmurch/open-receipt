import SwiftUI

struct ReceiptHistorySheet: View {
  let receipts: [ReceiptSummary]
  let isLoading: Bool
  @Binding var searchText: String
  let onOpen: (ReceiptSummary, ReceiptRecognition?) -> Void
  let onDelete: (ReceiptSummary) -> Void
  let onOpenRecentlyDeleted: () -> Void
  @Environment(ReceiptRecognitionCenter.self) private var recognitions

  var body: some View {
    VStack(spacing: 0) {
      ReceiptHistorySearchField(searchText: $searchText)
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 6)

      List {
        historyContent(filteredReceipts)

        if searchText.isEmpty {
          Section {
            Button(action: onOpenRecentlyDeleted) {
              HStack(spacing: 14) {
                Image(systemName: "trash")
                  .frame(width: 42)
                Text("Recently Deleted")
                Spacer()
                Image(systemName: "chevron.forward")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.tertiary)
              }
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.secondary)
              .padding(.top, 12)
              .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .historyRowStyle()
          }
        }
      }
      .listStyle(.plain)
      .contentMargins(.top, 0, for: .scrollContent)
      .scrollContentBackground(.hidden)
    }
  }

  @ViewBuilder
  private func historyContent(_ filteredReceipts: [ReceiptSummary]) -> some View {
    if isLoading && receipts.isEmpty {
      HStack {
        Spacer()
        ProgressView("Loading receipts")
        Spacer()
      }
      .padding(.vertical, 24)
      .historyRowStyle()
    } else if filteredReceipts.isEmpty {
      ContentUnavailableView(
        searchText.isEmpty ? "No Receipts" : "No Results",
        systemImage: searchText.isEmpty ? "receipt" : "magnifyingglass",
        description: Text(
          searchText.isEmpty
            ? "Your receipts will appear here."
            : "No receipts match your search.")
      )
      .frame(maxWidth: .infinity)
      .padding(.vertical, 24)
      .historyRowStyle()
    } else {
      ForEach(ReceiptLibrarySections.grouped(filteredReceipts)) { section in
        Section {
          ForEach(section.receipts) { receipt in
            let recognition = recognitions.recognition(for: receipt.id)
            ReceiptLibraryListRow(
              receipt: receipt,
              recognition: recognition,
              onOpen: { onOpen(receipt, recognition) },
              onDelete: { onDelete(receipt) }
            )
            .libraryRowStyle()
            .listRowSeparator(
              receipt.id == section.receipts.last?.id ? .hidden : .automatic, edges: .bottom
            )
            .deleteDisabled(recognition != nil)
          }
          .onDelete { offsets in
            for index in offsets where section.receipts.indices.contains(index) {
              onDelete(section.receipts[index])
            }
          }
        } header: {
          Text(section.title)
            .font(.title3.bold())
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.top, 8)
        }
      }
    }
  }

  private var filteredReceipts: [ReceiptSummary] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return receipts }

    return receipts.filter { receipt in
      [
        receipt.merchantName,
        recognitions.recognition(for: receipt.id)?.preview.merchantName,
        receipt.localDate,
        receipt.currency,
        receipt.localDate.flatMap(ReceiptLibraryDateFormatter.formatted),
      ]
      .compactMap { $0 }
      .contains { $0.localizedCaseInsensitiveContains(query) }
    }
  }
}

private struct ReceiptHistorySearchField: View {
  @Binding var searchText: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField("Search receipts", text: $searchText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

      if !searchText.isEmpty {
        Button("Clear search", systemImage: "xmark.circle.fill") {
          searchText = ""
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(.secondary)
      }
    }
    .font(.body)
    .padding(.horizontal, 14)
    .frame(height: 44)
    .background(.fill.tertiary, in: .capsule)
  }
}

extension View {
  func libraryRowStyle() -> some View {
    listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
  }

  func historyRowStyle() -> some View {
    listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
      .listRowSeparator(.hidden)
  }
}
