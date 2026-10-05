import XCTest

@testable import open_receipt

final class AdjustmentSplitSettingsTests: XCTestCase {
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = isolatedDefaults()
  }

  func testDefaultMethodIsProportionalWhenUnset() {
    XCTAssertEqual(AdjustmentSplitSettings.defaultMethod(in: defaults), .proportional)
  }

  func testDefaultMethodUsesStoredMethod() {
    defaults.set("even", forKey: AdjustmentSplitSettings.defaultMethodKey)

    XCTAssertEqual(AdjustmentSplitSettings.defaultMethod(in: defaults), .even)
  }

  func testDefaultMethodIgnoresInvalidStoredMethod() {
    defaults.set("weighted", forKey: AdjustmentSplitSettings.defaultMethodKey)

    XCTAssertEqual(AdjustmentSplitSettings.defaultMethod(in: defaults), .proportional)
  }
}
