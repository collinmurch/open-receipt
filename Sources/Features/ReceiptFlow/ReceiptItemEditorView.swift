import SwiftUI

struct ReceiptItemEditorView: View {
  private nonisolated enum Field: Hashable {
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
    let issues = item.issues

    Form {
      Section {
        TextField("Name", text: $item.description, axis: .vertical)
          .lineLimit(1...3)
          .focused($focusedField, equals: .name)
          .onChange(of: item.description) { _, name in
            guard name.contains(where: \.isNewline) else { return }
            item.description = Self.singleLine(name)
            // A multi-line field takes Return as a line break rather than a submit.
            focusedField = .quantity
          }
        LabeledContent("Quantity") {
          NumberField(
            "Quantity",
            value: $item.quantity,
            format: .number.precision(.fractionLength(0...3))
          )
          .multilineTextAlignment(.trailing)
          .focused($focusedField, equals: .quantity)
          .accessibilityLabel("Quantity")
        }
        .focusesOnTap($focusedField, equals: .quantity)
        LabeledContent("Line Total") {
          HStack {
            CurrencyAmountField(value: $item.lineTotal, currencyCode: currency)
              .multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .lineTotal)
              .accessibilityLabel("Line total")
            Button("Change Sign", systemImage: "plus.forwardslash.minus") {
              item.lineTotal = -item.lineTotal
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(item.lineTotal == 0)
          }
        }
        .focusesOnTap($focusedField, equals: .lineTotal)
      } header: {
        Text("Item")
      } footer: {
        if !issues.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(issues) { issue in
              Text(issue.message)
            }
          }
          .foregroundStyle(.orange)
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
    .dismissesKeyboardOnTap()
    .keyboardNavigation($focusedField, through: [.name, .quantity, .lineTotal])
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

nonisolated extension ReceiptItemEditorView {
  /// `name` with each line break replaced by a space, since an item's name is one line.
  static func singleLine(_ name: String) -> String {
    name.split(whereSeparator: \.isNewline).joined(separator: " ")
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
    let amountEach = item.lineTotal / count

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
            Text(amountEach.decimal, format: .currency(code: currency))
              .monospacedDigit()
              .contentTransition(.numericText(value: Double(amountEach)))
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
