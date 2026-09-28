import SwiftUI

struct ReceiptItemEditorView: View {
  @Binding var item: ReceiptDraftItem
  let currency: String
  let onSplit: (Int) -> Void
  let onDelete: () -> Void
  @State private var isSplitPresented = false
  @State private var haptic = HapticEvent()
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Form {
      Section("Item") {
        TextField("Name", text: $item.description, axis: .vertical)
          .lineLimit(1...3)
        LabeledContent("Quantity") {
          TextField(
            "Quantity",
            value: $item.quantity,
            format: .number.precision(.fractionLength(0...3))
          )
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .accessibilityLabel("Quantity")
        }
        LabeledContent("Line Total") {
          CurrencyAmountField(
            "Amount",
            value: $item.lineTotal,
            currencyCode: currency.count == 3 ? currency : "USD"
          )
          .multilineTextAlignment(.trailing)
          .accessibilityLabel("Line total")
        }
      }

      if item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !item.quantity.isFinite || item.quantity <= 0
      {
        Section("Fix Before Saving") {
          if item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label("Enter an item name.", systemImage: "exclamationmark.circle")
              .foregroundStyle(.red)
          }
          if !item.quantity.isFinite || item.quantity <= 0 {
            Label("Quantity must be greater than zero.", systemImage: "exclamationmark.circle")
              .foregroundStyle(.red)
          }
        }
      }

      Section {
        Button("Split Into Multiple Items", systemImage: "square.split.2x1") {
          isSplitPresented = true
        }
      }

      Section {
        Button("Delete Item", role: .destructive) {
          haptic.play(.removal)
          onDelete()
          dismiss()
        }
      }
    }
    .navigationTitle(item.description.isEmpty ? "New Item" : "Edit Item")
    .navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .haptics(haptic)
    .sheet(isPresented: $isSplitPresented) {
      ReceiptItemSplitSheet(
        item: item,
        currency: currency.count == 3 ? currency : "USD",
        onSplit: { count in
          isSplitPresented = false
          haptic.play(.success)
          onSplit(count)
          dismiss()
        })
    }
  }
}

private struct ReceiptItemSplitSheet: View {
  let item: ReceiptDraftItem
  let currency: String
  let onSplit: (Int) -> Void
  @State private var count: Int
  @Environment(\.dismiss) private var dismiss

  init(item: ReceiptDraftItem, currency: String, onSplit: @escaping (Int) -> Void) {
    self.item = item
    self.currency = currency
    self.onSplit = onSplit
    let quantity = item.quantity.isFinite ? Int(item.quantity.rounded()) : 1
    _count = State(initialValue: min(max(quantity, 2), Self.maximumCount))
  }

  private static let maximumCount = 50

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Stepper(value: $count, in: 2...Self.maximumCount) {
            LabeledContent("Items", value: "\(count)")
          }
          LabeledContent("Each") {
            Text(item.lineTotal / Double(count), format: .currency(code: currency))
              .monospacedDigit()
          }
        } footer: {
          Text(
            "Creates ^[\(count) item](inflect: true) at \((item.lineTotal / Double(count)).formatted(.currency(code: currency))) each."
          )
        }
      }
      .navigationTitle("Split Item")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Split") { onSplit(count) }
        }
      }
    }
    .presentationDetents([.medium])
  }
}
