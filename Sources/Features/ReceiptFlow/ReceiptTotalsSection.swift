import SwiftUI

private enum AdjustmentInputMode: CaseIterable, Identifiable {
  case amount
  case percentage

  var id: Self { self }
}

struct ReceiptTotalsSection: View {
  let draft: ReceiptDraft
  let isEditing: Bool
  let displayCurrency: String
  @Binding var haptic: HapticEvent
  @State private var tipInputMode = AdjustmentInputMode.amount
  @State private var savingsInputMode = AdjustmentInputMode.amount

  var body: some View {
    Section {
      if isEditing {
        if !draft.adjustments.isEmpty || draft.subtotalNeedsCorrection {
          amountField(
            "Subtotal",
            value: binding(\.subtotal),
            expectedValue: draft.subtotalNeedsCorrection ? draft.expectedSubtotal : nil)
        }
        if draft.adjustments.contains(.tax) {
          adjustmentField(.tax, value: binding(\.tax))
        }
        if draft.adjustments.contains(.tip) {
          percentageAdjustmentField(
            .tip,
            amount: binding(\.tip),
            percentage: binding(\.tipPercentage),
            mode: $tipInputMode)
        }
        if draft.adjustments.contains(.savings) {
          percentageAdjustmentField(
            .savings,
            amount: binding(\.savings),
            percentage: binding(\.savingsPercentage),
            mode: $savingsInputMode)
        }
        amountField(
          "Total",
          value: binding(\.total),
          isEmphasized: true,
          expectedValue: draft.totalNeedsCorrection ? draft.expectedTotal : nil)
      } else {
        if !draft.adjustments.isEmpty || draft.subtotalNeedsCorrection {
          totalRow(
            "Subtotal",
            value: draft.subtotal,
            expectedValue: draft.subtotalNeedsCorrection ? draft.expectedSubtotal : nil)
        }
        if draft.adjustments.contains(.tax) {
          totalRow("Tax", value: draft.tax)
        }
        if draft.adjustments.contains(.tip) {
          totalRow("Tip", value: draft.tip)
        }
        if draft.adjustments.contains(.savings) {
          totalRow("Savings", value: draft.savings == 0 ? 0 : -draft.savings)
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
        if isEditing, !draft.missingAdjustments.isEmpty {
          Menu {
            ForEach(draft.missingAdjustments) { adjustment in
              Button {
                draft.addAdjustment(adjustment)
              } label: {
                Label("Add \(adjustment.title)", systemImage: adjustment.systemImage)
              }
            }
          } label: {
            Label("Add Adjustment", systemImage: "plus")
              .labelStyle(.iconOnly)
          }
          .buttonStyle(.glass)
          .accessibilityLabel("Add Adjustment")
        }
        Spacer()
      }
    } footer: {
      fixTotalButton
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
          withAnimation(.smooth) { draft.fixTotal() }
          haptic.play(.success)
        }
        .buttonStyle(.glass)
        .tint(.orange)
        Spacer()
      }
      .padding(.top, 4)
    }
  }

  private func amountField(
    _ title: String,
    value: Binding<Double>,
    isEmphasized: Bool = false,
    expectedValue: Double? = nil
  ) -> some View {
    LabeledContent {
      VStack(alignment: .trailing, spacing: 2) {
        CurrencyAmountField("Amount", value: value, currencyCode: displayCurrency)
          .multilineTextAlignment(.trailing)
          .fontWeight(isEmphasized ? .semibold : .regular)
          .frame(minWidth: 100, idealWidth: 115, maxWidth: 130)
          .accessibilityLabel(title)
        correctionLabel(expectedValue, actualValue: value.wrappedValue)
      }
    } label: {
      Text(title)
        .fontWeight(isEmphasized ? .semibold : .regular)
    }
  }

  @ViewBuilder
  private func correctionLabel(_ expectedValue: Double?, actualValue: Double) -> some View {
    if let expectedValue {
      let difference = (actualValue - expectedValue).formatted(
        .currency(code: displayCurrency).sign(strategy: .always()))
      Text("Expected \(formattedCurrency(expectedValue)) (\(difference))")
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
            .accessibilityLabel(adjustment.title)
        } else {
          TextField("Percent", value: percentage, format: .number)
            .keyboardType(.decimalPad)
            .monospacedDigit()
            .accessibilityLabel("\(adjustment.title) percent")
          Text("%")
            .foregroundStyle(.secondary)
        }
      }
      .multilineTextAlignment(.trailing)
    } label: {
      adjustmentLabel(adjustment)
    }
  }

  private func adjustmentField(
    _ adjustment: ReceiptTotalAdjustment,
    value: Binding<Double>
  ) -> some View {
    LabeledContent {
      CurrencyAmountField("Amount", value: value, currencyCode: displayCurrency)
        .multilineTextAlignment(.trailing)
        .accessibilityLabel(adjustment.title)
    } label: {
      adjustmentLabel(adjustment)
    }
  }

  private func adjustmentLabel(_ adjustment: ReceiptTotalAdjustment) -> some View {
    HStack(spacing: 10) {
      Button(
        "Remove \(adjustment.title)",
        systemImage: "minus.circle.fill",
        role: .destructive
      ) {
        withAnimation(.smooth) { draft.removeAdjustment(adjustment) }
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

  private func formattedCurrency(_ value: Double) -> String {
    value.formatted(.currency(code: displayCurrency))
  }

  private func binding<Value>(
    _ keyPath: ReferenceWritableKeyPath<ReceiptDraft, Value>
  ) -> Binding<Value> {
    Binding(
      get: { draft[keyPath: keyPath] },
      set: { draft[keyPath: keyPath] = $0 })
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
