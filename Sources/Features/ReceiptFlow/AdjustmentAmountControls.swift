import SwiftUI

/// Whether an adjustment is entered as an amount or as a percentage of the items.
enum AdjustmentInputMode: CaseIterable, Identifiable {
  case amount
  case percentage

  var id: Self { self }

  func label(currencyCode: String) -> String {
    switch self {
    case .amount: ReceiptCurrency.symbol(currencyCode)
    case .percentage: "%"
    }
  }
}

/// A ready-made amount offered for an adjustment, such as a tip percentage or the tax a total
/// implies.
struct AdjustmentPreset: Hashable {
  let title: String
  let amount: Double

  /// `percentage` percent of `base`, rounded to the currency.
  static func percentage(
    _ percentage: Int,
    of base: Double,
    currencyCode: String
  ) -> AdjustmentPreset {
    AdjustmentPreset(
      title: Double(percentage).formatted(.percent.scale(1)),
      amount: ReceiptCurrency.rounded(base * Double(percentage) / 100, code: currencyCode))
  }

  /// The suggested tips, as percentages of `base`.
  static func tips(of base: Double, currencyCode: String) -> [AdjustmentPreset] {
    TipSettings.percentages().map { percentage($0, of: base, currencyCode: currencyCode) }
  }
}

extension [AdjustmentPreset] {
  /// The preset in the middle, which is chosen to start with.
  var middle: AdjustmentPreset? {
    isEmpty ? nil : self[count / 2]
  }
}

/// A choice between an adjustment's presets and a custom amount.
enum AdjustmentChoice: Hashable {
  case preset(AdjustmentPreset)
  case custom

  /// The choice showing `amount`: the preset it equals, unless a custom amount was chosen. Choosing
  /// a preset sets the amount to it.
  static func binding(
    amount: Binding<Double>,
    isCustom: Binding<Bool>,
    presets: [AdjustmentPreset]
  ) -> Binding<AdjustmentChoice> {
    Binding(
      get: {
        guard !isCustom.wrappedValue,
          let preset = presets.first(where: {
            abs($0.amount - amount.wrappedValue) < CurrencyAmountInput.tolerance
          })
        else { return .custom }
        return .preset(preset)
      },
      set: { choice in
        switch choice {
        case .preset(let preset):
          isCustom.wrappedValue = false
          amount.wrappedValue = preset.amount
        case .custom:
          isCustom.wrappedValue = true
        }
      })
  }
}

/// A segmented control choosing one of an adjustment's presets or a custom amount.
struct AdjustmentChoicePicker: View {
  let title: String
  let presets: [AdjustmentPreset]
  @Binding var choice: AdjustmentChoice

  var body: some View {
    Picker(title, selection: $choice) {
      ForEach(presets, id: \.self) { preset in
        Text(preset.title).tag(AdjustmentChoice.preset(preset))
      }
      Text("Custom").tag(AdjustmentChoice.custom)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .sensoryFeedback(.selection, trigger: choice)
  }
}

/// An adjustment's amount in a row: shown as it is for a preset, and entered as an amount or a
/// percentage of `base` when custom. Choosing custom focuses the field.
struct AdjustmentAmountValue: View {
  let title: String
  @Binding var amount: Double
  let isCustom: Bool
  let base: Double
  let currencyCode: String
  var isFocused: FocusState<Bool>.Binding
  @State private var mode = AdjustmentInputMode.amount

  var body: some View {
    Group {
      if isCustom {
        HStack {
          Picker("\(title) format", selection: $mode) {
            ForEach(AdjustmentInputMode.allCases) { mode in
              Text(mode.label(currencyCode: currencyCode)).tag(mode)
            }
          }
          .pickerStyle(.segmented)
          .frame(minWidth: 82)
          .fixedSize()
          field
        }
        .multilineTextAlignment(.trailing)
      } else {
        Text(amount, format: .currency(code: currencyCode))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .contentTransition(.numericText(value: amount))
      }
    }
    .onChange(of: isCustom) { _, isCustom in
      // The field exists once the amount it replaces is gone.
      if isCustom { Task { isFocused.wrappedValue = true } }
    }
    .onChange(of: mode) {
      Task { isFocused.wrappedValue = true }
    }
  }

  @ViewBuilder
  private var field: some View {
    switch mode {
    case .amount:
      CurrencyAmountField(value: $amount, currencyCode: currencyCode)
        .focused(isFocused)
        .accessibilityLabel(title)
    case .percentage:
      NumberField("Percent", value: percentage, format: .number.precision(.fractionLength(0...2)))
        .focused(isFocused)
        .accessibilityLabel("\(title) percent")
      Text("%")
        .foregroundStyle(.secondary)
    }
  }

  private var percentage: Binding<Double> {
    Binding(
      get: { base > 0 ? amount / base * 100 : 0 },
      set: { amount = ReceiptCurrency.rounded(max(0, base * $0 / 100), code: currencyCode) })
  }
}
