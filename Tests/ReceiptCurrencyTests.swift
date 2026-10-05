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
