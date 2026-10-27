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
  /// The percentage of a base the preset is, or `nil` when it isn't one.
  var percentage: Int? = nil

  /// `percentage` percent of `base`, rounded to the currency.
  static func percentage(
    _ percentage: Int,
    of base: Double,
    currencyCode: String
  ) -> AdjustmentPreset {
    AdjustmentPreset(
      title: Double(percentage).formatted(.percent.scale(1)),
      amount: ReceiptCurrency.rounded(base * Double(percentage) / 100, code: currencyCode),
      percentage: percentage)
  }

  /// The suggested tips, as `percentages` of `base`.
  static func tips(
    of base: Double,
    percentages: [Int] = TipSettings.percentages(),
    currencyCode: String
  ) -> [AdjustmentPreset] {
    percentages.map { percentage($0, of: base, currencyCode: currencyCode) }
  }
}

/// The line under a tip that says what it's a percentage of, such as "20% of $44.70 before tax".
enum TipBaseCaption {
  /// `isAfterSavings` says whether `base` has the receipt's savings taken off, and is `nil` when
  /// the receipt has none.
  static func text(
    tip: Double,
    base: Double,
    isAfterTax: Bool,
    isAfterSavings: Bool? = nil,
    currencyCode: String
  ) -> String? {
    guard tip > 0, base > 0 else { return nil }
    let percentage = (tip / base).formatted(.percent.precision(.fractionLength(0...1)))
    let amount = base.formatted(.currency(code: currencyCode))
    return
      "\(percentage) of \(amount) \(phrase(isAfterTax: isAfterTax, isAfterSavings: isAfterSavings))"
  }

  private static func phrase(isAfterTax: Bool, isAfterSavings: Bool?) -> String {
    switch (isAfterTax, isAfterSavings) {
    case (false, nil): "before tax"
    case (false, false): "before tax and savings"
    case (false, true): "after savings, before tax"
    case (true, nil): "after tax"
    case (true, true): "after tax and savings"
    case (true, false): "after tax, before savings"
    }
  }
}

extension [AdjustmentPreset] {
  /// The preset in the middle, which is chosen to start with.
  var middle: AdjustmentPreset? {
    isEmpty ? nil : self[count / 2]
  }

  /// The preset whose amount is `amount`.
  func first(matching amount: Double) -> AdjustmentPreset? {
    first { abs($0.amount - amount) < CurrencyAmountInput.tolerance }
  }
}

/// A choice between an adjustment's presets and a custom amount.
enum AdjustmentChoice: Hashable {
  case preset(AdjustmentPreset)
  case custom

  /// The choice showing `amount`: the preset it equals, unless a custom amount was chosen.
  static func current(
    amount: Double,
    isCustom: Bool,
    presets: [AdjustmentPreset]
  ) -> AdjustmentChoice {
    guard !isCustom, let preset = presets.first(matching: amount) else { return .custom }
    return .preset(preset)
  }

  /// The current choice, where choosing a preset sets the amount to it.
  static func binding(
    amount: Binding<Double>,
    isCustom: Binding<Bool>,
    presets: [AdjustmentPreset]
  ) -> Binding<AdjustmentChoice> {
    Binding(
      get: {
        current(
          amount: amount.wrappedValue, isCustom: isCustom.wrappedValue, presets: presets)
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

/// An adjustment's row: its amount shown as it is for a preset, and entered when custom. Choosing
/// custom focuses the field as `field`.
struct AdjustmentAmountRow<Field: Hashable & Sendable, Label: View>: View {
  let title: String
  @Binding var amount: Double
  let isCustom: Bool
  let currencyCode: String
  let focus: FocusState<Field?>.Binding
  let field: Field
  @ViewBuilder let label: Label

  var body: some View {
    LabeledContent {
      value
    } label: {
      label
    }
    .onChange(of: isCustom) { _, isCustom in
      // The field exists once the amount it replaces is gone.
      if isCustom { Task { focus.wrappedValue = field } }
    }
  }

  @ViewBuilder
  private var value: some View {
    if isCustom {
      CurrencyAmountField(value: $amount, currencyCode: currencyCode)
        .multilineTextAlignment(.trailing)
        .focused(focus, equals: field)
        .accessibilityLabel(title)
    } else {
      Text(amount, format: .currency(code: currencyCode))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .contentTransition(.numericText(value: amount))
    }
  }
}

extension View {
  /// Makes a tap anywhere on the view choose a custom amount and focus `field`, so a row's padding
  /// answers the tap too.
  func choosesCustomAmount<Field: Hashable & Sendable>(
    _ choice: Binding<AdjustmentChoice>,
    focusing field: Field,
    in focus: FocusState<Field?>.Binding
  ) -> some View {
    contentShape(.rect)
      .onTapGesture {
        withAnimation(.settle) { choice.wrappedValue = .custom }
        focus.wrappedValue = field
      }
  }
}
