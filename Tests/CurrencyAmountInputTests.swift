import XCTest

@testable import open_receipt

final class CurrencyAmountInputTests: XCTestCase {
  func testTypingDigitShiftsIntoCents() {
    XCTAssertEqual(edit("$1.23", to: "$1.234"), 12.34, accuracy: 0.000_1)
  }

  func testDeletingLastDigitShiftsOutOfCents() {
    XCTAssertEqual(edit("$12.34", to: "$12.3"), 1.23, accuracy: 0.000_1)
  }

  func testDeletingRepeatedlyReachesZero() {
    var text = "$1.23"
    for _ in 0..<5 {
      text = CurrencyAmountInput.text(
        for: edit(text, to: String(text.dropLast())), currencyCode: "USD")
    }

    XCTAssertEqual(text, CurrencyAmountInput.text(for: 0, currencyCode: "USD"))
  }

  func testTypingFromZeroBuildsAmount() {
    var text = CurrencyAmountInput.text(for: 0, currencyCode: "USD")
    for digit in ["4", "5", "6", "7"] {
      text = CurrencyAmountInput.text(for: edit(text, to: text + digit), currencyCode: "USD")
    }

    XCTAssertEqual(text, CurrencyAmountInput.text(for: 45.67, currencyCode: "USD"))
  }

  func testDeletingTrailingSymbolRemovesLastDigit() {
    XCTAssertEqual(edit("12,34 €", to: "12,34 ", currencyCode: "EUR"), 1.23, accuracy: 0.000_1)
  }

  func testShownAmountIgnoresGroupingSeparators() {
    let amount = CurrencyAmountInput.amount(in: "$1,234.56", currencyCode: "USD")

    XCTAssertEqual(amount, 1_234.56, accuracy: 0.000_1)
  }

  func testShownAmountReadsSign() {
    let amount = CurrencyAmountInput.amount(in: "-$3.50", currencyCode: "USD")

    XCTAssertEqual(amount, -3.5, accuracy: 0.000_1)
  }

  func testShownAmountOfOverlongTextDoesNotOverflow() {
    let amount = CurrencyAmountInput.amount(
      in: String(repeating: "9", count: 40), currencyCode: "USD")

    XCTAssertGreaterThan(amount, 0)
  }

  func testNegativeSignIsPreserved() {
    XCTAssertEqual(edit("-$3.00", to: "-$3.001", isNegative: true), -30.01, accuracy: 0.000_1)
  }

  func testZeroFractionCurrencyUsesWholeUnits() {
    XCTAssertEqual(ReceiptCurrency.fractionDigits("JPY"), 0)
    XCTAssertEqual(edit("¥12", to: "¥123", currencyCode: "JPY"), 123)
  }

  func testPastedAmountIsParsed() {
    XCTAssertEqual(edit("$0.00", to: "$0.00$19.99"), 19.99, accuracy: 0.000_1)
  }

  func testTypingOverSelectedAmountStartsFresh() {
    XCTAssertEqual(edit("$12.34", to: "5", replacingAll: true), 0.05, accuracy: 0.000_1)
  }

  func testDeletingSelectedAmountReachesZero() {
    XCTAssertEqual(edit("$12.34", to: "", replacingAll: true), 0)
  }

  func testPastingOverSelectedAmountReplacesIt() {
    XCTAssertEqual(edit("$12.34", to: "$8.99", replacingAll: true), 8.99, accuracy: 0.000_1)
  }

  func testPastingShorterAmountOverSelectedAmountReplacesIt() {
    XCTAssertEqual(edit("$12.34", to: "$12", replacingAll: true), 12, accuracy: 0.000_1)
  }

  func testPastingAmountStartingWithSelectedAmountReplacesIt() {
    XCTAssertEqual(edit("¥1", to: "¥1,500", replacingAll: true, currencyCode: "JPY"), 1_500)
  }

  func testPastingLongerAmountOverSelectedAmountReplacesIt() {
    XCTAssertEqual(edit("¥1", to: "¥100", replacingAll: true, currencyCode: "JPY"), 100)
  }

  func testTypingOneDigitOverSelectedSingleDigitEntersIt() {
    XCTAssertEqual(edit("¥1", to: "7", replacingAll: true, currencyCode: "JPY"), 7)
  }

  func testOverlongInputKeepsPreviousAmount() {
    let amount = edit("$1,234,567,890.12", to: "$1,234,567,890.123")

    XCTAssertEqual(amount, 1_234_567_890.12, accuracy: 0.001)
  }

  func testOverlongPasteKeepsPreviousAmount() {
    XCTAssertEqual(edit("$1.23", to: "15551234567", replacingAll: true), 1.23, accuracy: 0.000_1)
  }

  func testPasteCountsFractionDigitsTowardLimit() {
    XCTAssertEqual(edit("$1.23", to: "99999999999", replacingAll: true), 1.23, accuracy: 0.000_1)
  }

  func testPasteWithinLimitIsEntered() {
    let amount = edit("$1.23", to: "9999999999.99", replacingAll: true)

    XCTAssertEqual(amount, 9_999_999_999.99, accuracy: 0.001)
  }

  func testTypingOverNegativeAmountKeepsItNegative() {
    let amount = edit("-$5.00", to: "7", replacingAll: true, isNegative: true)

    XCTAssertEqual(amount, -0.07, accuracy: 0.000_1)
  }

  func testDeletingFromNegativeAmountKeepsItNegative() {
    XCTAssertEqual(edit("-$5.00", to: "-$5.0", isNegative: true), -0.5, accuracy: 0.000_1)
  }

  func testTypingAfterDeletingNegativeToZeroKeepsItNegative() {
    let zero = CurrencyAmountInput.text(for: 0, currencyCode: "USD")

    XCTAssertEqual(edit(zero, to: zero + "7", isNegative: true), -0.07, accuracy: 0.000_1)
  }

  func testPastingWholeAmountKeepsItsScale() {
    XCTAssertEqual(edit("$0.00", to: "$12", replacingAll: true), 12, accuracy: 0.000_1)
  }

  func testPastingOneFractionDigitKeepsItsScale() {
    XCTAssertEqual(edit("$0.00", to: "12.5", replacingAll: true), 12.5, accuracy: 0.000_1)
  }

  func testPastingGroupedAmountIsParsed() {
    XCTAssertEqual(edit("$0.00", to: "$1,234.56", replacingAll: true), 1_234.56, accuracy: 0.000_1)
  }

  func testPastingUsesLocaleDecimalSeparator() {
    let amount = edit(
      "0,00 €", to: "1.234,56", replacingAll: true, currencyCode: "EUR",
      locale: Locale(identifier: "de_DE"))

    XCTAssertEqual(amount, 1_234.56, accuracy: 0.000_1)
  }

  func testPastingNegativeAmountIsNegative() {
    XCTAssertEqual(edit("$0.00", to: "-3.50", replacingAll: true), -3.5, accuracy: 0.000_1)
  }

  func testPastingTrailingMinusIsNegative() {
    XCTAssertEqual(edit("$0.00", to: "3.50-", replacingAll: true), -3.5, accuracy: 0.000_1)
  }

  func testPastingDashBetweenDigitsIsNotNegative() {
    XCTAssertGreaterThan(edit("$0.00", to: "12-50", replacingAll: true), 0)
  }

  func testPastingPositiveAmountOverNegativeReplacesSign() {
    let amount = edit("-$5.00", to: "$3.50", replacingAll: true, isNegative: true)

    XCTAssertEqual(amount, 3.5, accuracy: 0.000_1)
  }

  func testPastingExtraFractionDigitsRounds() {
    XCTAssertEqual(edit("$0.00", to: "8.5266", replacingAll: true), 8.53, accuracy: 0.000_1)
  }

  func testPastingHalfCentRoundsAwayFromZero() {
    XCTAssertEqual(edit("$0.00", to: "1.005", replacingAll: true), 1.01, accuracy: 0.000_1)
  }

  func testPastingTextWithoutDigitsKeepsAmount() {
    XCTAssertEqual(edit("$1.23", to: "$1.23abc"), 1.23, accuracy: 0.000_1)
  }

  func testSwitchingCurrencyIsNotAnEdit() {
    let amount = CurrencyAmountInput.amount(
      replacing: CurrencyAmountInput.text(for: 12.34, currencyCode: "USD"),
      with: CurrencyAmountInput.text(for: 12.34, currencyCode: "JPY"), replacingAll: false,
      value: 12.34, isNegative: false, currencyCode: "JPY")

    XCTAssertNil(amount)
  }

  func testShowingValueWithExtraDecimalsIsNotAnEdit() {
    let amount = CurrencyAmountInput.amount(
      replacing: "", with: CurrencyAmountInput.text(for: 8.5266, currencyCode: "USD"),
      replacingAll: false, value: 8.5266, isNegative: false, currencyCode: "USD")

    XCTAssertNil(amount)
  }

  func testTypingIsAnEdit() {
    let shown = CurrencyAmountInput.text(for: 1.23, currencyCode: "USD")

    let amount = CurrencyAmountInput.amount(
      replacing: shown, with: shown + "4", replacingAll: false, value: 1.23, isNegative: false,
      currencyCode: "USD")

    XCTAssertEqual(amount ?? 0, 12.34, accuracy: 0.000_1)
  }

  private func edit(
    _ oldText: String,
    to newText: String,
    replacingAll: Bool = false,
    isNegative: Bool = false,
    currencyCode: String = "USD",
    locale: Locale = Locale(identifier: "en_US")
  ) -> Double {
    let value = CurrencyAmountInput.amount(in: oldText, currencyCode: currencyCode)
    return CurrencyAmountInput.amount(
      replacing: oldText, with: newText, replacingAll: replacingAll, value: value,
      isNegative: isNegative, currencyCode: currencyCode, locale: locale) ?? .nan
  }
}
