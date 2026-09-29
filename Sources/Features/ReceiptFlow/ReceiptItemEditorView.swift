import SwiftUI

struct ReceiptItemEditorView: View {
  @Binding var item: ReceiptDraftItem
  let currency: String
  let onSplit: (Int) -> Void
  let onDelete: () -> Void
  @State private var isSplitPresented = false
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let currencyCode = ReceiptCurrency.displayCode(currency)
    let issues = item.validationIssues

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
          CurrencyAmountField("Amount", value: $item.lineTotal, currencyCode: currencyCode)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel("Line total")
        }
      }

      if !issues.isEmpty {
        Section("Fix Before Saving") {
          ForEach(issues) { issue in
            Label(issue.itemMessage, systemImage: "exclamationmark.circle")
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
          onDelete()
          dismiss()
        }
      }
    }
    .navigationTitle(item.description.isEmpty ? "New Item" : "Edit Item")
    .navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .sheet(isPresented: $isSplitPresented) {
      ReceiptItemSplitSheet(
        item: item,
        currency: currencyCode,
        onSplit: { count in
          isSplitPresented = false
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
    let amountEach = item.lineTotal / Double(count)

    NavigationStack {
      Form {
        Section {
          Stepper(value: $count, in: 2...Self.maximumCount) {
            LabeledContent("Items", value: "\(count)")
          }
          LabeledContent("Each") {
            Text(amountEach, format: .currency(code: currency))
              .monospacedDigit()
              .contentTransition(.numericText(value: amountEach))
              .animation(.smooth, value: count)
          }
        } footer: {
          Text(
            "Creates ^[\(count) item](inflect: true) at \(amountEach.formatted(.currency(code: currency))) each."
          )
        }
      }
      .navigationTitle("Split Item")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Split") { onSplit(count) }
        }
      }
    }
    .presentationDetents([.medium])
  }
}

extension ReceiptEditorValidationIssue {
  fileprivate var itemMessage: String {
    switch self {
    case .missingItemDescription: "Enter an item name."
    case .invalidItemQuantity: "Quantity must be greater than zero."
    case .invalidItemTotal: "Enter a valid line total."
    default: message
    }
  }
}
