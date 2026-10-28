import XCTest

@testable import open_receipt

final class CurrencySettingsTests: XCTestCase {
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = isolatedDefaults()
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
}
