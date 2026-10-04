import SwiftUI
import Synchronization

/// A currency text field that enters digits from the right, like a register: typing
/// appends a digit to the smallest unit and deleting removes the last digit. The whole amount
/// is selected when the field gains focus, so typing replaces it.
struct CurrencyAmountField: View {
  let title: String
  @Binding var value: Double
  let currencyCode: String
  let isEmphasized: Bool
  @State private var text = ""
  @State private var selection: TextSelection?
  @FocusState private var isFocused: Bool

  init(
    _ title: String,
    value: Binding<Double>,
    currencyCode: String,
    isEmphasized: Bool = false
  ) {
    self.title = title
    _value = value
    self.currencyCode = currencyCode
    self.isEmphasized = isEmphasized
  }

  var body: some View {
    TextField(title, text: $text, selection: $selection)
      .keyboardType(.numberPad)
      .monospacedDigit()
      .focused($isFocused)
      .formValueStyle(isFocused: isFocused, isEmphasized: isEmphasized)
      .onAppear { text = CurrencyAmountInput.text(for: value, currencyCode: currencyCode) }
      .onChange(of: text) { oldText, newText in
        let amount = CurrencyAmountInput.amount(
          replacing: oldText,
          with: newText,
          fractionDigits: CurrencyAmountInput.fractionDigits(currencyCode: currencyCode))
        let formatted = CurrencyAmountInput.text(for: amount, currencyCode: currencyCode)
        if formatted != newText { text = formatted }
        if abs(amount - value) >= CurrencyAmountInput.tolerance { value = amount }
        moveInsertionPointToEnd()
      }
      .onChange(of: value) { _, newValue in
        let fractionDigits = CurrencyAmountInput.fractionDigits(currencyCode: currencyCode)
        let shown = CurrencyAmountInput.amount(
          replacing: text, with: text, fractionDigits: fractionDigits)
        if abs(shown - newValue) >= CurrencyAmountInput.tolerance {
          text = CurrencyAmountInput.text(for: newValue, currencyCode: currencyCode)
        }
      }
      .onChange(of: currencyCode) { _, newCode in
        text = CurrencyAmountInput.text(for: value, currencyCode: newCode)
      }
      .onChange(of: isFocused) { _, focused in
        guard focused else { return }
        // UIKit places the insertion point from the tap after focus changes.
        Task { selection = allSelected }
      }
      .onChange(of: selection) {
        if selection != allSelected { moveInsertionPointToEnd() }
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
  private static let maximumDigits = 12

  private struct CurrencyDetails {
    let fractionDigits: Int
    let symbol: String
  }

  private static let detailsByCurrencyCode = Mutex<[String: CurrencyDetails]>([:])

  static func fractionDigits(currencyCode: String) -> Int {
    details(currencyCode: currencyCode).fractionDigits
  }

  static func symbol(currencyCode: String) -> String {
    details(currencyCode: currencyCode).symbol
  }

  /// Number formatters are expensive to create, so each currency's details are read once.
  private static func details(currencyCode: String) -> CurrencyDetails {
    if let cached = detailsByCurrencyCode.withLock({ $0[currencyCode] }) {
      return cached
    }
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currencyCode
    let details = CurrencyDetails(
      fractionDigits: formatter.maximumFractionDigits,
      symbol: formatter.currencySymbol)
    detailsByCurrencyCode.withLock { $0[currencyCode] = details }
    return details
  }

  static func text(for amount: Double, currencyCode: String) -> String {
    amount.formatted(.currency(code: currencyCode))
  }

  /// Returns the amount for `newText` after an edit from `oldText`. A deletion that removed
  /// only formatting, such as a trailing currency symbol, removes the last digit instead.
  static func amount(replacing oldText: String, with newText: String, fractionDigits: Int)
    -> Double
  {
    var digits = newText.compactMap(\.wholeNumberValue)
    if newText.count < oldText.count, digits == oldText.compactMap(\.wholeNumberValue),
      !digits.isEmpty
    {
      digits.removeLast()
    }
    let significant = digits.drop { $0 == 0 }
    if significant.count > maximumDigits {
      return amount(replacing: oldText, with: oldText, fractionDigits: fractionDigits)
    }
    let units = significant.reduce(0) { $0 * 10 + $1 }
    let magnitude = Double(units) / pow(10, Double(fractionDigits))
    let isNegative = newText.contains("-") || newText.contains("\u{2212}")
    return isNegative && magnitude != 0 ? -magnitude : magnitude
  }
}
