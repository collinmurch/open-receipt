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
}

/// A choice between an adjustment's presets and a custom amount.
enum AdjustmentChoice: Hashable {
  case preset(AdjustmentPreset)
  case custom

  /// The choice of the preset at `percentage`, or custom when it's `nil` or none of `presets`.
  init(percentage: Int?, presets: [AdjustmentPreset]) {
    let preset = percentage.flatMap { percentage in
      presets.first { $0.percentage == percentage }
    }
    self = preset.map(Self.preset) ?? .custom
  }

  /// The chosen preset's percentage, or `nil` for a custom amount or a preset that isn't one.
  var percentage: Int? {
    guard case .preset(let preset) = self else { return nil }
    return preset.percentage
  }
}

extension Binding<AdjustmentChoice> {
  /// The choice, focusing `field` when custom is chosen, once its field has replaced the amount.
  @MainActor
  func focusingCustom<Field: Hashable & Sendable>(
    _ field: Field,
    in focus: FocusState<Field?>.Binding
  ) -> Binding<AdjustmentChoice> {
    Binding(
      get: { wrappedValue },
      set: { choice, transaction in
        self.transaction(transaction).wrappedValue = choice
        if choice == .custom { Task { @MainActor in focus.wrappedValue = field } }
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

/// An adjustment's row: its amount shown as it is for a preset, and entered as `field` when
/// custom.
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
  /// Makes a tap anywhere on the view choose a custom amount, so a row's padding answers the tap
  /// too. Pass a choice made with `focusingCustom(_:in:)` to focus the amount's field as well.
  func choosesCustomAmount(_ choice: Binding<AdjustmentChoice>) -> some View {
    contentShape(.rect)
      .onTapGesture {
        withAnimation(.settle) { choice.wrappedValue = .custom }
      }
  }
}
