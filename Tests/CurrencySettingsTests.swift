import UIKit
import XCTest

@testable import open_receipt

final class CurrencySettingsTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "CurrencySettingsTests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testDefaultCodeIsUSDWhenUnset() {
    XCTAssertEqual(CurrencySettings.defaultCode(in: defaults), "USD")
  }

  func testDefaultCodeUsesStoredCode() {
    defaults.set("EUR", forKey: CurrencySettings.defaultCodeKey)

    XCTAssertEqual(CurrencySettings.defaultCode(in: defaults), "EUR")
  }

  func testDefaultCodeIgnoresInvalidStoredCode() {
    defaults.set("euro", forKey: CurrencySettings.defaultCodeKey)

    XCTAssertEqual(CurrencySettings.defaultCode(in: defaults), "USD")
  }

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
