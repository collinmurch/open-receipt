import SwiftUI

/// A currency text field that enters digits from the right, like a register: typing
/// appends a digit to the smallest unit and deleting removes the last digit, keeping the
/// amount's sign while the field is focused. The whole amount is selected when the field gains
/// focus, so typing replaces it; otherwise the insertion point stays at the end. Pasting enters
/// the pasted amount as written. Only edits change the value: formatting it, such as for a new
/// currency, never does.
struct CurrencyAmountField: View {
  @Binding var value: Double
  let currencyCode: String
  let isEmphasized: Bool
  @State private var text = ""
  @State private var selection: TextSelection?
  @State private var selectedText: String?
  @State private var isNegative = false
  @FocusState private var isFocused: Bool

  init(value: Binding<Double>, currencyCode: String, isEmphasized: Bool = false) {
    _value = value
    self.currencyCode = currencyCode
    self.isEmphasized = isEmphasized
  }

  var body: some View {
    TextField("Amount", text: $text, selection: $selection)
      .keyboardType(.numberPad)
      .monospacedDigit()
      .focused($isFocused)
      .formValueStyle(isFocused: isFocused, isEmphasized: isEmphasized)
      .onAppear { text = CurrencyAmountInput.text(for: value, currencyCode: currencyCode) }
      .onChange(of: text) { oldText, newText in
        defer { moveInsertionPointToEnd() }
        let replacingAll = selectedText == oldText
        selectedText = nil
        guard
          let amount = CurrencyAmountInput.amount(
            replacing: oldText, with: newText, replacingAll: replacingAll, value: value,
            isNegative: isNegative, currencyCode: currencyCode)
        else { return }
        let formatted = CurrencyAmountInput.text(for: amount, currencyCode: currencyCode)
        if formatted != newText { text = formatted }
        if abs(amount - value) >= CurrencyAmountInput.tolerance { value = amount }
      }
      .onChange(of: value) { _, newValue in
        if newValue != 0 { isNegative = newValue < 0 }
        let shown = CurrencyAmountInput.amount(in: text, currencyCode: currencyCode)
        if abs(shown - newValue) >= CurrencyAmountInput.tolerance {
          text = CurrencyAmountInput.text(for: newValue, currencyCode: currencyCode)
        }
      }
      .onChange(of: currencyCode) { _, newCode in
        text = CurrencyAmountInput.text(for: value, currencyCode: newCode)
      }
      .onChange(of: isFocused) { _, focused in
        isNegative = value < 0
        selectedText = nil
        guard focused else { return }
        // UIKit places the insertion point from the tap after focus changes.
        Task { selection = allSelected }
      }
      .onChange(of: selection) {
        if selection == allSelected {
          selectedText = text
        } else {
          // A selection change without an edit, such as a tap, deselects the amount.
          if text == selectedText { selectedText = nil }
          moveInsertionPointToEnd()
        }
      }
  }

  /// Selecting everything is the one selection besides the end that keeps register entry
  /// coherent: typing or deleting replaces the whole amount.
  private var allSelected: TextSelection {
    TextSelection(range: text.startIndex..<text.endIndex)
  }

  private func moveInsertionPointToEnd() {
    let end = TextSelection(insertionPoint: text.endIndex)
    if selection != end { selection = end }
  }
}

enum CurrencyAmountInput {
  static let tolerance = 0.000_5
  private static let maximumUnits = 1e12

  static func text(for amount: Double, currencyCode: String) -> String {
    amount.formatted(.currency(code: currencyCode))
  }

  /// The amount `text` shows, reading its digits in `currencyCode`'s smallest unit.
  static func amount(in text: String, currencyCode: String) -> Double {
    signed(
      units(text.compactMap(\.wholeNumberValue)), isNegative: isNegative(text),
      currencyCode: currencyCode)
  }

  /// Returns the amount an edit from `oldText` to `newText` enters, or `nil` when `newText` only
  /// shows `value`, as it does after the field formats the value itself. The edit replaced the
  /// whole text when `replacingAll` is true and changed its end otherwise.
  ///
  /// One inserted character is a keystroke: digits enter from the right, deleting removes the
  /// last digit, and the amount takes the sign `isNegative` gives. Inserting more, as pasting
  /// does, enters the inserted text as a whole amount written in `locale`. An edit that enters
  /// no amount, or one too long to hold, keeps `value`.
  static func amount(
    replacing oldText: String,
    with newText: String,
    replacingAll: Bool,
    value: Double,
    isNegative: Bool,
    currencyCode: String,
    locale: Locale = .current
  ) -> Double? {
    guard newText != text(for: value, currencyCode: currencyCode) else { return nil }
    let inserted =
      replacingAll
      ? Substring(newText) : newText.hasPrefix(oldText) ? newText.dropFirst(oldText.count) : ""
    if inserted.count > 1 {
      return pastedAmount(inserted, currencyCode: currencyCode, locale: locale) ?? value
    }
    var digits = newText.compactMap(\.wholeNumberValue)
    if !replacingAll, newText.count < oldText.count,
      digits == oldText.compactMap(\.wholeNumberValue), !digits.isEmpty
    {
      digits.removeLast()
    }
    let units = units(digits)
    guard units < maximumUnits else { return value }
    return signed(units, isNegative: isNegative, currencyCode: currencyCode)
  }

  private static func pastedAmount(
    _ text: Substring, currencyCode: String, locale: Locale
  ) -> Double? {
    let decimalSeparator = locale.decimalSeparator ?? "."
    var number = ""
    for character in text {
      if let digit = character.wholeNumberValue {
        number += String(digit)
      } else if String(character) == decimalSeparator {
        number += "."
      }
    }
    guard let magnitude = Double(number), magnitude < maximumUnits else { return nil }
    let units = Double(ReceiptCurrency.minorUnits(magnitude, code: currencyCode))
    guard units < maximumUnits else { return nil }
    return signed(units, isNegative: isNegative(text), currencyCode: currencyCode)
  }

  private static func units(_ digits: [Int]) -> Double {
    digits.reduce(0) { $0 * 10 + Double($1) }
  }

  private static func signed(_ units: Double, isNegative: Bool, currencyCode: String) -> Double {
    let magnitude = units / pow(10, Double(ReceiptCurrency.fractionDigits(currencyCode)))
    return isNegative && magnitude != 0 ? -magnitude : magnitude
  }

  /// Whether `text` has a minus sign before its first digit or after its last, as in "-$3.50"
  /// or a receipt's "3.50-". A dash between digits isn't a sign.
  private static func isNegative(_ text: some StringProtocol) -> Bool {
    let isMinus = { (character: Character) in character == "-" || character == "\u{2212}" }
    let isDigit = { (character: Character) in character.wholeNumberValue != nil }
    return text.prefix(while: { !isDigit($0) }).contains(where: isMinus)
      || text.reversed().prefix(while: { !isDigit($0) }).contains(where: isMinus)
  }
}
