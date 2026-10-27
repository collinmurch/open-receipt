import UIKit
import XCTest

@testable import open_receipt

final class ReceiptCurrencyTests: XCTestCase {
  func testDisplayCodeKeepsValidCode() {
    XCTAssertEqual(ReceiptCurrency.displayCode("GBP", fallback: "EUR"), "GBP")
  }

  func testDisplayCodeUsesFallbackForMissingCode() {
    XCTAssertEqual(ReceiptCurrency.displayCode(nil, fallback: "EUR"), "EUR")
  }

  func testDisplayCodeUsesFallbackForIncompleteCode() {
    XCTAssertEqual(ReceiptCurrency.displayCode("EU", fallback: "JPY"), "JPY")
  }

  func testMinorUnitsRoundsHalfCentUp() {
    XCTAssertEqual(ReceiptCurrency.minorUnits(1.005, code: "USD"), 101)
  }

  func testMinorUnitsRoundsNegativeHalfCentAwayFromZero() {
    XCTAssertEqual(ReceiptCurrency.minorUnits(-1.005, code: "USD"), -101)
  }

  func testMinorUnitsRoundsHalfYenUp() {
    XCTAssertEqual(ReceiptCurrency.minorUnits(2.5, code: "JPY"), 3)
  }

  func testMinorUnitsRoundsHalfFilsUp() {
    XCTAssertEqual(ReceiptCurrency.minorUnits(1.0005, code: "KWD"), 1_001)
  }

  func testMinorUnitsIgnoresFloatingPointErrorInSums() {
    XCTAssertEqual(ReceiptCurrency.minorUnits(0.1 + 0.2, code: "USD"), 30)
  }

  func testMinorUnitsRoundsJustBelowHalfDown() {
    XCTAssertEqual(ReceiptCurrency.minorUnits(1.0049, code: "USD"), 100)
  }

  func testMinorUnitsOfLargeAmount() {
    XCTAssertEqual(ReceiptCurrency.minorUnits(12_345_678.905, code: "USD"), 1_234_567_891)
  }

  func testMinorUnitsOfNonFiniteAmountIsZero() {
    XCTAssertEqual(ReceiptCurrency.minorUnits(.nan, code: "USD"), 0)
  }

  func testMinorUnitsOfUncountableAmountIsZero() {
    XCTAssertEqual(ReceiptCurrency.minorUnits(1e300, code: "USD"), 0)
  }

  func testRoundedRoundsHalfCentUp() {
    XCTAssertEqual(ReceiptCurrency.rounded(2.675, code: "USD"), 2.68)
  }

  func testPercentageOfAmountRoundsHalfCentUp() {
    let preset = AdjustmentPreset.percentage(15, of: 6.70, currencyCode: "USD")

    XCTAssertEqual(preset.amount, 1.01)
  }

  func testSymbolsIncludeDollarSignForUSD() {
    XCTAssertTrue(ReceiptCurrency.symbols("USD").contains("$"))
  }

  func testSymbolsIncludeEuroSign() {
    XCTAssertTrue(ReceiptCurrency.symbols("EUR").contains("€"))
  }

  func testSymbolsIncludeNativeSign() {
    XCTAssertTrue(ReceiptCurrency.symbols("PLN").contains("zł"))
  }

  func testSymbolNameUsesCurrencySign() {
    XCTAssertEqual(ReceiptCurrency.symbolName("EUR"), "eurosign")
  }

  func testSymbolNameIgnoresCase() {
    XCTAssertEqual(ReceiptCurrency.symbolName("gbp"), "sterlingsign")
  }

  func testSymbolNameUsesBanknoteWithoutSign() {
    XCTAssertEqual(ReceiptCurrency.symbolName("XAF"), "banknote")
  }

  func testSymbolNamesExist() {
    for code in Locale.commonISOCurrencyCodes {
      let name = ReceiptCurrency.symbolName(code)
      XCTAssertNotNil(UIImage(systemName: name), "\(code) uses missing symbol \(name)")
    }
  }
}
