import SwiftUI

struct ReceiptTotalsSection: View {
  /// The identity of the section's first row, the subtotal, for scrolling to it.
  nonisolated static let scrollID = ReceiptEditField.amount(.subtotal)

  @Bindable var draft: ReceiptDraft
  let isEditing: Bool
  /// Whether the tip is entered as an amount rather than chosen from the suggestions.
  @Binding var isTipCustom: Bool
  var focusedField: FocusState<ReceiptEditField?>.Binding
  @Binding var haptic: HapticEvent
  /// Adds an item for the amount the items are short, and opens it to be named.
  let onAddItem: (Double) -> Void
  @State private var savingsInputMode = AdjustmentInputMode.amount

  /// The amounts typed in while editing, in the order they're listed. A tip chosen from the
  /// suggestions has no field.
  static func editableFields(of draft: ReceiptDraft, isTipCustom: Bool) -> [ReceiptAmountField] {
    let tipChoice = AdjustmentChoice.current(
      amount: draft.tip, isCustom: isTipCustom, presets: draft.tipPresets)
    let adjustments = draft.adjustmentOrder.filter { adjustment in
      draft.adjustments.contains(adjustment) && (adjustment != .tip || tipChoice == .custom)
    }
    return [.subtotal] + adjustments.map(ReceiptAmountField.adjustment) + [.total]
  }

  var body: some View {
    let balance = draft.balance
    let notice = ReceiptBalanceNotice.notice(for: draft)

    Section {
      if isEditing {
        editingRows(balance: balance)
      } else {
        summaryRows(balance: balance, flaggedField: notice?.field)
      }
      if let notice {
        ReceiptBalanceNoticeRow(notice: notice, currencyCode: displayCurrency, perform: perform)
      }
    } header: {
      Text("Totals")
    }
  }

  /// Every adjustment keeps its place while editing: its field when the receipt has it, and a row
  /// that adds it when it doesn't. Dragging the tip past tax or savings bases it on the amount
  /// before or after them.
  @ViewBuilder
  private func editingRows(balance: ReceiptBalance) -> some View {
    amountField(
      "Subtotal", field: .subtotal,
      value: Binding(get: { draft.subtotal }, set: { draft.setSubtotal($0) })
    )
    .id(Self.scrollID)
    ForEach(draft.adjustmentOrder) { adjustment in
      adjustmentRow(adjustment, balance: balance)
        .id(ReceiptEditField.amount(.adjustment(adjustment)))
        .moveDisabled(!canReorder(adjustment))
        .accessibilityActions { reorderActions(for: adjustment) }
    }
    .onMove(perform: moveAdjustments)
    splitPicker
    amountField("Total", field: .total, value: $draft.total, isEmphasized: true)
      .id(ReceiptEditField.amount(.total))
  }

  @ViewBuilder
  private func summaryRows(
    balance: ReceiptBalance,
    flaggedField: ReceiptAmountField?
  ) -> some View {
    if !draft.adjustments.isEmpty || flaggedField == .subtotal {
      totalRow(
        "Subtotal", field: .subtotal, value: balance.subtotal,
        isFlagged: flaggedField == .subtotal
      )
      .id(Self.scrollID)
    }
    ForEach(draft.adjustmentOrder.filter(draft.adjustments.contains)) { kind in
      totalRow(
        kind.title, field: .adjustment(kind), value: draft.adjustments.signedAmount(of: kind),
        caption: caption(for: kind, balance: balance))
    }
    splitPicker
    totalRow(
      "Total", field: .total, value: draft.total, isEmphasized: true,
      isFlagged: flaggedField == .total)
  }

  /// How the extras are shared, shown once the receipt has any.
  @ViewBuilder
  private var splitPicker: some View {
    if !draft.adjustments.isEmpty {
      Picker(selection: $draft.adjustmentSplitMethod) {
        ForEach(ReceiptAdjustmentSplitMethod.allCases) { method in
          Text(method.title)
            .tag(method)
        }
      } label: {
        Text("Split Extras")
          .foregroundStyle(isEditing ? .primary : .secondary)
      }
      .pickerStyle(.menu)
    }
  }

  /// Whether moving adjustments can change the tip: there's a tip, and tax or savings to move it
  /// past.
  private var canReorderAdjustments: Bool {
    draft.adjustments.contains(.tip)
      && (draft.adjustments.contains(.tax) || draft.adjustments.contains(.savings))
  }

  private func canReorder(_ adjustment: ReceiptTotalAdjustment) -> Bool {
    canReorderAdjustments && draft.adjustments.contains(adjustment)
  }

  private func moveAdjustments(from source: IndexSet, to destination: Int) {
    var order = draft.adjustmentOrder
    order.move(fromOffsets: source, toOffset: destination)
    withAnimation(.settle) { draft.setAdjustmentOrder(order) }
    haptic.play(.selection)
  }

  @ViewBuilder
  private func reorderActions(for adjustment: ReceiptTotalAdjustment) -> some View {
    if canReorder(adjustment), let index = draft.adjustmentOrder.firstIndex(of: adjustment) {
      if index > draft.adjustmentOrder.startIndex {
        Button("Move Up") { moveAdjustments(from: [index], to: index - 1) }
      }
      if index < draft.adjustmentOrder.endIndex - 1 {
        Button("Move Down") { moveAdjustments(from: [index], to: index + 2) }
      }
    }
  }

  @ViewBuilder
  private func adjustmentRow(
    _ adjustment: ReceiptTotalAdjustment,
    balance: ReceiptBalance
  ) -> some View {
    if draft.adjustments.contains(adjustment) {
      adjustmentEditor(adjustment, balance: balance)
    } else {
      addAdjustmentRow(adjustment)
    }
  }

  @ViewBuilder
  private func adjustmentEditor(
    _ adjustment: ReceiptTotalAdjustment,
    balance: ReceiptBalance
  ) -> some View {
    switch adjustment {
    case .tax:
      amountField(ReceiptTotalAdjustment.tax.title, field: .adjustment(.tax), value: $draft.tax) {
        adjustmentLabel(.tax)
      }
    case .tip:
      tipEditor
    case .savings:
      percentageAdjustmentField(
        .savings,
        amount: $draft.savings,
        percentage: $draft.savingsPercentage,
        mode: $savingsInputMode,
        caption: caption(for: .savings, balance: balance))
    }
  }

  /// The tip, chosen from the suggested percentages or entered like the other amounts.
  private var tipEditor: some View {
    let presets = draft.tipPresets
    let choice = AdjustmentChoice.binding(
      amount: $draft.tip, isCustom: $isTipCustom, presets: presets)
    let field = ReceiptEditField.amount(.adjustment(.tip))
    return VStack(alignment: .leading, spacing: 12) {
      AdjustmentAmountRow(
        title: ReceiptTotalAdjustment.tip.title, amount: $draft.tip,
        isCustom: choice.wrappedValue == .custom, currencyCode: displayCurrency,
        focus: focusedField, field: field
      ) {
        adjustmentLabel(.tip)
      }
      .choosesCustomAmount(choice, focusing: field, in: focusedField)
      AdjustmentChoicePicker(
        title: "Tip Amount", presets: presets, choice: choice.animation(.settle))
      if let caption = draft.tipCaption(for: draft.tip) {
        Text(
          canReorderAdjustments
            ? "\(caption). Press and drag to reorder; the tip is based on what’s above it."
            : caption
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .contentTransition(.numericText())
      }
    }
  }

  private func addAdjustmentRow(_ adjustment: ReceiptTotalAdjustment) -> some View {
    Button {
      withAnimation(.settle) {
        if adjustment == .tip {
          isTipCustom = false
          draft.addAdjustment(.tip, amount: draft.tipPresets.middle?.amount ?? 0)
        } else {
          draft.addAdjustment(adjustment)
        }
      }
      haptic.play(.selection)
      // The field exists once the row has been replaced. A tip starts at a suggestion instead.
      if adjustment != .tip {
        Task { focusedField.wrappedValue = .amount(.adjustment(adjustment)) }
      }
    } label: {
      AddRowLabel("Add \(adjustment.title)")
    }
  }

  private func totalRow(
    _ label: String,
    field: ReceiptAmountField,
    value: Double,
    isEmphasized: Bool = false,
    isFlagged: Bool = false,
    caption: String? = nil
  ) -> some View {
    HStack(alignment: .firstTextBaseline) {
      rowTitle(
        Text(label)
          .foregroundStyle(isEmphasized ? .primary : .secondary)
          .fontWeight(isEmphasized ? .semibold : .regular),
        field: field, caption: caption)
      Spacer()
      Text(value, format: .currency(code: displayCurrency))
        .font(.body.monospacedDigit())
        .fontWeight(isEmphasized ? .semibold : .regular)
        .foregroundStyle(isFlagged ? AnyShapeStyle(Color.orange) : valueStyle(isEmphasized))
        .contentTransition(.numericText(value: value))
    }
  }

  private func valueStyle(_ isEmphasized: Bool) -> AnyShapeStyle {
    isEmphasized
      ? AnyShapeStyle(HierarchicalShapeStyle.primary)
      : AnyShapeStyle(HierarchicalShapeStyle.secondary)
  }

  /// Notes savings that were already taken off above the subtotal, so the list still adds up.
  private func caption(for adjustment: ReceiptTotalAdjustment, balance: ReceiptBalance) -> String? {
    guard adjustment == .savings, !balance.subtractsSavingsFromSubtotal else { return nil }
    return balance.printedSubtotal == nil ? "Included in item prices" : "Included in subtotal"
  }

  private func perform(_ action: ReceiptBalanceNotice.Action) {
    focusedField.wrappedValue = nil
    switch action {
    case .addItem(let amount):
      onAddItem(amount)
      return
    case .setSubtotal(let amount):
      withAnimation(.settle) { draft.setSubtotal(amount) }
    case .setTotal(let amount):
      withAnimation(.settle) { draft.total = amount }
    }
    haptic.play(.success)
  }

  private func amountField(
    _ title: String,
    field: ReceiptAmountField,
    value: Binding<Double>,
    isEmphasized: Bool = false
  ) -> some View {
    amountField(title, field: field, value: value, isEmphasized: isEmphasized) {
      rowTitle(Text(title).fontWeight(isEmphasized ? .semibold : .regular), field: field)
    }
  }

  private func amountField(
    _ title: String,
    field: ReceiptAmountField,
    value: Binding<Double>,
    isEmphasized: Bool = false,
    @ViewBuilder label: () -> some View
  ) -> some View {
    LabeledContent {
      CurrencyAmountField(
        value: value, currencyCode: displayCurrency, isEmphasized: isEmphasized
      )
      .multilineTextAlignment(.trailing)
      .fontWeight(isEmphasized ? .semibold : .regular)
      .frame(minWidth: 100, idealWidth: 115, maxWidth: 130)
      .focused(focusedField, equals: .amount(field))
      .accessibilityLabel(title)
    } label: {
      label()
    }
    .focusesOnTap(focusedField, equals: .amount(field))
  }

  private func percentageAdjustmentField(
    _ adjustment: ReceiptTotalAdjustment,
    amount: Binding<Double>,
    percentage: Binding<Double>,
    mode: Binding<AdjustmentInputMode>,
    caption: String?
  ) -> some View {
    let field = ReceiptEditField.amount(.adjustment(adjustment))
    return LabeledContent {
      HStack {
        Picker("\(adjustment.title) format", selection: mode) {
          ForEach(AdjustmentInputMode.allCases) { option in
            Text(option.label(currencyCode: displayCurrency)).tag(option)
          }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 82)
        .fixedSize()

        if mode.wrappedValue == .amount {
          CurrencyAmountField(value: amount, currencyCode: displayCurrency)
            .focused(focusedField, equals: field)
            .accessibilityLabel(adjustment.title)
        } else {
          NumberField(
            "Percent",
            value: percentage,
            format: .number.precision(.fractionLength(0...2))
          )
          .focused(focusedField, equals: field)
          .accessibilityLabel("\(adjustment.title) percent")
          Text("%")
            .foregroundStyle(.secondary)
        }
      }
      .multilineTextAlignment(.trailing)
    } label: {
      adjustmentLabel(adjustment, caption: caption)
    }
    .focusesOnTap(focusedField, equals: field)
  }

  private func adjustmentLabel(
    _ adjustment: ReceiptTotalAdjustment,
    caption: String? = nil
  ) -> some View {
    HStack(spacing: 10) {
      Button(
        "Remove \(adjustment.title)",
        systemImage: "minus.circle.fill",
        role: .destructive
      ) {
        withAnimation(.settle) { draft.removeAdjustment(adjustment) }
        haptic.play(.removal)
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .foregroundStyle(.red)
      rowTitle(Text(adjustment.title), field: .adjustment(adjustment), caption: caption)
    }
  }

  /// A row's title, marked with the field's issues, over its caption.
  private func rowTitle(
    _ title: Text,
    field: ReceiptAmountField,
    caption: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      title
        .receiptIssues(draft.issues(at: .amount(field)))
      if let caption {
        Text(caption)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
  }

  private var displayCurrency: String {
    draft.displayCurrency
  }
}
