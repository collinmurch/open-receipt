import XCTest

@testable import open_receipt

final class CurrencyAmountInputTests: XCTestCase {
  func testTypingDigitShiftsIntoCents() {
    let amount = CurrencyAmountInput.amount(
      replacing: "$1.23", with: "$1.234", fractionDigits: 2)

    XCTAssertEqual(amount, 12.34, accuracy: 0.000_1)
  }

  func testDeletingLastDigitShiftsOutOfCents() {
    let amount = CurrencyAmountInput.amount(
      replacing: "$12.34", with: "$12.3", fractionDigits: 2)

    XCTAssertEqual(amount, 1.23, accuracy: 0.000_1)
  }

  func testDeletingRepeatedlyReachesZero() {
    var text = "$1.23"
    for _ in 0..<5 {
      let amount = CurrencyAmountInput.amount(
        replacing: text, with: String(text.dropLast()), fractionDigits: 2)
      text = CurrencyAmountInput.text(for: amount, currencyCode: "USD")
    }

    XCTAssertEqual(text, CurrencyAmountInput.text(for: 0, currencyCode: "USD"))
  }

  func testTypingFromZeroBuildsAmount() {
    var text = CurrencyAmountInput.text(for: 0, currencyCode: "USD")
    for digit in ["4", "5", "6", "7"] {
      let amount = CurrencyAmountInput.amount(
        replacing: text, with: text + digit, fractionDigits: 2)
      text = CurrencyAmountInput.text(for: amount, currencyCode: "USD")
    }

    XCTAssertEqual(text, CurrencyAmountInput.text(for: 45.67, currencyCode: "USD"))
  }

  func testDeletingTrailingSymbolRemovesLastDigit() {
    let amount = CurrencyAmountInput.amount(
      replacing: "12,34 €", with: "12,34 ", fractionDigits: 2)

    XCTAssertEqual(amount, 1.23, accuracy: 0.000_1)
  }

  func testGroupingSeparatorsAreIgnored() {
    let amount = CurrencyAmountInput.amount(
      replacing: "$1,234.56", with: "$1,234.56", fractionDigits: 2)

    XCTAssertEqual(amount, 1_234.56, accuracy: 0.000_1)
  }

  func testNegativeSignIsPreserved() {
    let amount = CurrencyAmountInput.amount(
      replacing: "-$3.00", with: "-$3.001", fractionDigits: 2)

    XCTAssertEqual(amount, -30.01, accuracy: 0.000_1)
  }

  func testZeroFractionCurrencyUsesWholeUnits() {
    let fractionDigits = CurrencyAmountInput.fractionDigits(currencyCode: "JPY")

    let amount = CurrencyAmountInput.amount(
      replacing: "¥12", with: "¥123", fractionDigits: fractionDigits)

    XCTAssertEqual(fractionDigits, 0)
    XCTAssertEqual(amount, 123)
  }

  func testPastedAmountIsParsed() {
    let amount = CurrencyAmountInput.amount(
      replacing: "$0.00", with: "$0.00$19.99", fractionDigits: 2)

    XCTAssertEqual(amount, 19.99, accuracy: 0.000_1)
  }

  func testTypingOverSelectedAmountStartsFresh() {
    let amount = CurrencyAmountInput.amount(
      replacing: "$12.34", with: "5", fractionDigits: 2)

    XCTAssertEqual(amount, 0.05, accuracy: 0.000_1)
  }

  func testDeletingSelectedAmountReachesZero() {
    let amount = CurrencyAmountInput.amount(
      replacing: "$12.34", with: "", fractionDigits: 2)

    XCTAssertEqual(amount, 0)
  }

  func testPastingOverSelectedAmountReplacesIt() {
    let amount = CurrencyAmountInput.amount(
      replacing: "$12.34", with: "$8.99", fractionDigits: 2)

    XCTAssertEqual(amount, 8.99, accuracy: 0.000_1)
  }

  func testOverlongInputKeepsPreviousAmount() {
    let amount = CurrencyAmountInput.amount(
      replacing: "$1,234,567,890.12", with: "$1,234,567,890.123", fractionDigits: 2)

    XCTAssertEqual(amount, 1_234_567_890.12, accuracy: 0.001)
  }
}
