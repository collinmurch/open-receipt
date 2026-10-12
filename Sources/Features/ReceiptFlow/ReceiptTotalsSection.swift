import SwiftUI

struct ReceiptTotalsSection: View {
  @Bindable var draft: ReceiptDraft
  let isEditing: Bool
  @Binding var haptic: HapticEvent
  @State private var isTipCustom = false
  @FocusState private var isTipFocused: Bool
  @State private var savingsInputMode = AdjustmentInputMode.amount
  @FocusState private var focusedField: ReceiptAmountField?

  var body: some View {
    let (expectedSubtotal, expectedTotal) = draft.corrections
    let showsSubtotal = !draft.adjustments.isEmpty || expectedSubtotal != nil

    Section {
      if isEditing {
        editingRows(expectedSubtotal: expectedSubtotal, expectedTotal: expectedTotal)
      } else {
        summaryRows(
          showsSubtotal: showsSubtotal, expectedSubtotal: expectedSubtotal,
          expectedTotal: expectedTotal)
      }
    } header: {
      Text("Totals")
    } footer: {
      if isEditing, expectedTotal != nil {
        fixTotalButton
      }
    }
  }

  /// Every adjustment keeps its place while editing: its field when the receipt has it, and a row
  /// that adds it when it doesn't.
  @ViewBuilder
  private func editingRows(expectedSubtotal: Double?, expectedTotal: Double?) -> some View {
    amountField(
      "Subtotal", field: .subtotal, value: $draft.subtotal, expectedValue: expectedSubtotal)
    ForEach(ReceiptTotalAdjustment.allCases) { adjustment in
      if draft.adjustments.contains(adjustment) {
        adjustmentEditor(adjustment)
      } else {
        addAdjustmentRow(adjustment)
      }
    }
    amountField(
      "Total",
      field: .total,
      value: $draft.total,
      isEmphasized: true,
      expectedValue: expectedTotal)
  }

  @ViewBuilder
  private func summaryRows(
    showsSubtotal: Bool,
    expectedSubtotal: Double?,
    expectedTotal: Double?
  ) -> some View {
    if showsSubtotal {
      totalRow(
        "Subtotal", field: .subtotal, value: draft.subtotal, expectedValue: expectedSubtotal)
    }
    ForEach(ReceiptTotalAdjustment.allCases.filter(draft.adjustments.contains)) { kind in
      totalRow(
        kind.title, field: .adjustment(kind), value: draft.adjustments.signedAmount(of: kind))
    }
    totalRow(
      "Total", field: .total, value: draft.total, isEmphasized: true,
      expectedValue: expectedTotal)
  }

  @ViewBuilder
  private func adjustmentEditor(_ adjustment: ReceiptTotalAdjustment) -> some View {
    switch adjustment {
    case .tax:
      adjustmentField(.tax, value: $draft.tax)
    case .tip:
      tipEditor
    case .savings:
      percentageAdjustmentField(
        .savings,
        amount: $draft.savings,
        percentage: $draft.savingsPercentage,
        mode: $savingsInputMode)
    }
  }

  /// The tip, chosen from the suggested percentages or entered like the other amounts.
  private var tipEditor: some View {
    let presets = AdjustmentPreset.tips(of: draft.expectedSubtotal, currencyCode: displayCurrency)
    let choice = AdjustmentChoice.binding(
      amount: $draft.tip, isCustom: $isTipCustom, presets: presets)
    return VStack(spacing: 12) {
      LabeledContent {
        AdjustmentAmountValue(
          title: ReceiptTotalAdjustment.tip.title, amount: $draft.tip,
          isCustom: choice.wrappedValue == .custom, base: draft.expectedSubtotal,
          currencyCode: displayCurrency, isFocused: $isTipFocused)
      } label: {
        adjustmentLabel(.tip)
      }
      .contentShape(.rect)
      .onTapGesture {
        withAnimation(.settle) { choice.wrappedValue = .custom }
        isTipFocused = true
      }
      AdjustmentChoicePicker(
        title: "Tip Amount", presets: presets, choice: choice.animation(.settle))
    }
  }

  private func addAdjustmentRow(_ adjustment: ReceiptTotalAdjustment) -> some View {
    Button {
      withAnimation(.settle) {
        draft.adjustments.add(adjustment)
        if adjustment == .tip {
          isTipCustom = false
          let presets = AdjustmentPreset.tips(
            of: draft.expectedSubtotal, currencyCode: displayCurrency)
          draft.tip = presets.middle?.amount ?? 0
        }
      }
      haptic.play(.selection)
      // The field exists once the row has been replaced. A tip starts at a suggestion instead.
      if adjustment != .tip {
        Task { focusedField = .adjustment(adjustment) }
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
    expectedValue: Double? = nil
  ) -> some View {
    HStack {
      Text(label)
        .foregroundStyle(isEmphasized ? .primary : .secondary)
        .fontWeight(isEmphasized ? .semibold : .regular)
        .receiptIssues(draft.issues(at: .amount(field)))
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(value, format: .currency(code: displayCurrency))
          .font(.body.monospacedDigit())
          .fontWeight(isEmphasized ? .semibold : .regular)
          .foregroundStyle(isEmphasized ? .primary : .secondary)
          .contentTransition(.numericText(value: value))
        correctionLabel(expectedValue, actualValue: value)
      }
    }
  }

  private var fixTotalButton: some View {
    HStack {
      Spacer()
      Button("Fix Total", systemImage: "wand.and.sparkles") {
        withAnimation(.settle) { draft.fixTotal() }
        haptic.play(.success)
      }
      .buttonStyle(.bordered)
      .tint(.orange)
      Spacer()
    }
    .padding(.top, 4)
  }

  private func amountField(
    _ title: String,
    field: ReceiptAmountField,
    value: Binding<Double>,
    isEmphasized: Bool = false,
    expectedValue: Double? = nil
  ) -> some View {
    LabeledContent {
      VStack(alignment: .trailing, spacing: 2) {
        CurrencyAmountField(
          value: value, currencyCode: displayCurrency, isEmphasized: isEmphasized
        )
        .multilineTextAlignment(.trailing)
        .fontWeight(isEmphasized ? .semibold : .regular)
        .frame(minWidth: 100, idealWidth: 115, maxWidth: 130)
        .focused($focusedField, equals: field)
        .accessibilityLabel(title)
        correctionLabel(expectedValue, actualValue: value.wrappedValue)
      }
    } label: {
      Text(title)
        .fontWeight(isEmphasized ? .semibold : .regular)
        .receiptIssues(draft.issues(at: .amount(field)))
    }
    .focusesOnTap($focusedField, equals: field)
  }

  @ViewBuilder
  private func correctionLabel(_ expectedValue: Double?, actualValue: Double) -> some View {
    if let expectedValue {
      let expected = expectedValue.formatted(.currency(code: displayCurrency))
      let difference = (actualValue - expectedValue).formatted(
        .currency(code: displayCurrency).sign(strategy: .always()))
      Text("Expected \(expected) (\(difference))")
        .font(.caption)
        .foregroundStyle(.orange)
        .lineLimit(1)
    }
  }

  private func percentageAdjustmentField(
    _ adjustment: ReceiptTotalAdjustment,
    amount: Binding<Double>,
    percentage: Binding<Double>,
    mode: Binding<AdjustmentInputMode>
  ) -> some View {
    LabeledContent {
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
            .focused($focusedField, equals: .adjustment(adjustment))
            .accessibilityLabel(adjustment.title)
        } else {
          NumberField(
            "Percent",
            value: percentage,
            format: .number.precision(.fractionLength(0...2))
          )
          .focused($focusedField, equals: .adjustment(adjustment))
          .accessibilityLabel("\(adjustment.title) percent")
          Text("%")
            .foregroundStyle(.secondary)
        }
      }
      .multilineTextAlignment(.trailing)
    } label: {
      adjustmentLabel(adjustment)
    }
    .focusesOnTap($focusedField, equals: .adjustment(adjustment))
  }

  private func adjustmentField(
    _ adjustment: ReceiptTotalAdjustment,
    value: Binding<Double>
  ) -> some View {
    LabeledContent {
      CurrencyAmountField(value: value, currencyCode: displayCurrency)
        .multilineTextAlignment(.trailing)
        .focused($focusedField, equals: .adjustment(adjustment))
        .accessibilityLabel(adjustment.title)
    } label: {
      adjustmentLabel(adjustment)
    }
    .focusesOnTap($focusedField, equals: .adjustment(adjustment))
  }

  private func adjustmentLabel(_ adjustment: ReceiptTotalAdjustment) -> some View {
    HStack(spacing: 10) {
      Button(
        "Remove \(adjustment.title)",
        systemImage: "minus.circle.fill",
        role: .destructive
      ) {
        withAnimation(.settle) { draft.adjustments.remove(adjustment) }
        haptic.play(.removal)
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .foregroundStyle(.red)
      Text(adjustment.title)
        .receiptIssues(draft.issues(at: .amount(.adjustment(adjustment))))
    }
  }

  private var displayCurrency: String {
    draft.displayCurrency
  }
}
