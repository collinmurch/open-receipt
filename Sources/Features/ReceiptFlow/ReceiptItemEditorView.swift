import SwiftUI

struct ReceiptItemEditorView: View {
  private enum Field: Hashable {
    case name
    case quantity
    case lineTotal
  }

  @Binding var item: ReceiptDraftItem
  /// The display currency code the item's amounts are formatted with.
  let currency: String
  let onSplit: (Int) -> Void
  let onDelete: () -> Void
  /// Whether the item was blank when opened, which keeps the title from changing while typing.
  @State private var isNew: Bool
  @State private var isSplitPresented = false
  @State private var isDeleteConfirmationPresented = false
  @FocusState private var focusedField: Field?
  @Environment(\.dismiss) private var dismiss

  init(
    item: Binding<ReceiptDraftItem>,
    currency: String,
    onSplit: @escaping (Int) -> Void,
    onDelete: @escaping () -> Void
  ) {
    _item = item
    self.currency = currency
    self.onSplit = onSplit
    self.onDelete = onDelete
    _isNew = State(initialValue: item.wrappedValue.description.isEmpty)
  }

  var body: some View {
    let issues = item.validationIssues

    Form {
      Section("Item") {
        TextField("Name", text: $item.description, axis: .vertical)
          .lineLimit(1...3)
          .focused($focusedField, equals: .name)
        LabeledContent("Quantity") {
          TextField(
            "Quantity",
            value: $item.quantity,
            format: .number.precision(.fractionLength(0...3))
          )
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .focused($focusedField, equals: .quantity)
          .accessibilityLabel("Quantity")
        }
        LabeledContent("Line Total") {
          CurrencyAmountField("Amount", value: $item.lineTotal, currencyCode: currency)
            .multilineTextAlignment(.trailing)
            .focused($focusedField, equals: .lineTotal)
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
          isDeleteConfirmationPresented = true
        }
        .confirmationDialog(
          "Delete This Item?",
          isPresented: $isDeleteConfirmationPresented,
          titleVisibility: .visible
        ) {
          Button("Delete Item", role: .destructive) {
            onDelete()
            dismiss()
          }
        } message: {
          Text("Its assignments are removed from the split.")
        }
      }
    }
    .navigationTitle(isNew ? "New Item" : "Edit Item")
    .navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar {
      // Number pads have no return key, so the keyboard gets its own way to close.
      if focusedField == .quantity || focusedField == .lineTotal {
        ToolbarItem(placement: .keyboard) {
          Button("Done") { focusedField = nil }
        }
      }
    }
    .onAppear {
      if isNew { focusedField = .name }
    }
    .sheet(isPresented: $isSplitPresented) {
      ReceiptItemSplitSheet(
        item: item,
        currency: currency,
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
            LabeledContent("Items") {
              Text(count, format: .number)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
                .animation(.smooth, value: count)
            }
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
          Button("Split", systemImage: "checkmark", role: .confirm) { onSplit(count) }
        }
      }
      .sensoryFeedback(trigger: count) { oldCount, newCount in
        newCount > oldCount ? .increase : .decrease
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
