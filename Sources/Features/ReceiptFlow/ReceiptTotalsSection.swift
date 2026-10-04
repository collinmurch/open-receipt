import SwiftUI

private enum AdjustmentInputMode: CaseIterable, Identifiable {
  case amount
  case percentage

  var id: Self { self }
}

private enum TotalsField: Hashable {
  case subtotal
  case adjustment(ReceiptTotalAdjustment)
  case total
}

struct ReceiptTotalsSection: View {
  @Bindable var draft: ReceiptDraft
  let isEditing: Bool
  @Binding var haptic: HapticEvent
  @State private var tipInputMode = AdjustmentInputMode.amount
  @State private var savingsInputMode = AdjustmentInputMode.amount
  @FocusState private var focusedField: TotalsField?

  var body: some View {
    Section {
      if isEditing {
        if !draft.adjustments.isEmpty || draft.subtotalNeedsCorrection {
          amountField(
            "Subtotal",
            field: .subtotal,
            value: $draft.subtotal,
            expectedValue: draft.subtotalNeedsCorrection ? draft.expectedSubtotal : nil)
        }
        if draft.adjustments.contains(.tax) {
          adjustmentField(.tax, value: $draft.tax)
        }
        if draft.adjustments.contains(.tip) {
          percentageAdjustmentField(
            .tip,
            amount: $draft.tip,
            percentage: $draft.tipPercentage,
            mode: $tipInputMode)
        }
        if draft.adjustments.contains(.savings) {
          percentageAdjustmentField(
            .savings,
            amount: $draft.savings,
            percentage: $draft.savingsPercentage,
            mode: $savingsInputMode)
        }
        amountField(
          "Total",
          field: .total,
          value: $draft.total,
          isEmphasized: true,
          expectedValue: draft.totalNeedsCorrection ? draft.expectedTotal : nil)
      } else {
        if !draft.adjustments.isEmpty || draft.subtotalNeedsCorrection {
          totalRow(
            "Subtotal",
            value: draft.subtotal,
            expectedValue: draft.subtotalNeedsCorrection ? draft.expectedSubtotal : nil)
        }
        ForEach(ReceiptTotalAdjustment.allCases.filter(draft.adjustments.contains)) { kind in
          totalRow(kind.title, value: draft.signedAmount(of: kind))
        }
        totalRow(
          "Total",
          value: draft.total,
          isEmphasized: true,
          expectedValue: draft.totalNeedsCorrection ? draft.expectedTotal : nil)
      }
    } header: {
      HStack {
        Text("Totals")
        if isEditing, !draft.adjustments.missing.isEmpty {
          Menu {
            ForEach(draft.adjustments.missing) { adjustment in
              Button {
                withAnimation(.settle) { draft.adjustments.add(adjustment) }
                haptic.play(.selection)
              } label: {
                Label("Add \(adjustment.title)", systemImage: adjustment.systemImage)
              }
            }
          } label: {
            Label("Add Adjustment", systemImage: "plus")
              .labelStyle(.iconOnly)
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.circle)
          .accessibilityLabel("Add Adjustment")
        }
        Spacer()
      }
    } footer: {
      fixTotalButton
    }
    .toolbar {
      // Number pads have no return key, so the keyboard gets its own way to close.
      if focusedField != nil {
        ToolbarItem(placement: .keyboard) {
          Button("Done") { focusedField = nil }
        }
      }
    }
  }

  private func totalRow(
    _ label: String,
    value: Double,
    isEmphasized: Bool = false,
    expectedValue: Double? = nil
  ) -> some View {
    HStack {
      Text(label)
        .foregroundStyle(isEmphasized ? .primary : .secondary)
        .fontWeight(isEmphasized ? .semibold : .regular)
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

  @ViewBuilder
  private var fixTotalButton: some View {
    if isEditing, draft.totalNeedsCorrection {
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
  }

  private func amountField(
    _ title: String,
    field: TotalsField,
    value: Binding<Double>,
    isEmphasized: Bool = false,
    expectedValue: Double? = nil
  ) -> some View {
    LabeledContent {
      VStack(alignment: .trailing, spacing: 2) {
        CurrencyAmountField(
          "Amount", value: value, currencyCode: displayCurrency, isEmphasized: isEmphasized
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
    }
    .focusesOnTap($focusedField, equals: field)
  }

  @ViewBuilder
  private func correctionLabel(_ expectedValue: Double?, actualValue: Double) -> some View {
    if let expectedValue {
      let difference = (actualValue - expectedValue).formatted(
        .currency(code: displayCurrency).sign(strategy: .always()))
      Text("Expected \(expectedValue.formatted(.currency(code: displayCurrency))) (\(difference))")
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
            Text(label(for: option)).tag(option)
          }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 82)
        .fixedSize()

        if mode.wrappedValue == .amount {
          CurrencyAmountField("Amount", value: amount, currencyCode: displayCurrency)
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
      CurrencyAmountField("Amount", value: value, currencyCode: displayCurrency)
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
    }
  }

  private func label(for mode: AdjustmentInputMode) -> String {
    switch mode {
    case .amount: CurrencyAmountInput.symbol(currencyCode: displayCurrency)
    case .percentage: "%"
    }
  }

  private var displayCurrency: String {
    draft.displayCurrency
  }
}

extension ReceiptTotalAdjustment {
  fileprivate var systemImage: String {
    switch self {
    case .tax: "percent"
    case .tip: "dollarsign"
    case .savings: "tag"
    }
  }
}
