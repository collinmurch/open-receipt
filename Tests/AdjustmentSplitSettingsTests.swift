import XCTest

@testable import open_receipt

final class AdjustmentSplitSettingsTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "AdjustmentSplitSettingsTests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
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
