import XCTest

@testable import open_receipt

final class TipSettingsTests: XCTestCase {
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = isolatedDefaults()
  }

  func testPercentagesStartAtInitialSuggestions() {
    XCTAssertEqual(TipSettings.percentages(in: defaults), [18, 20, 22])
  }

  func testPercentagesUseStoredValue() {
    defaults.set(25, forKey: TipSettings.percentageKeys[2])

    XCTAssertEqual(TipSettings.percentages(in: defaults), [18, 20, 25])
  }

  func testPercentagesAreSorted() {
    defaults.set(30, forKey: TipSettings.percentageKeys[0])

    XCTAssertEqual(TipSettings.percentages(in: defaults), [20, 22, 30])
  }

  func testPercentagesDropRepeats() {
    defaults.set(20, forKey: TipSettings.percentageKeys[0])

    XCTAssertEqual(TipSettings.percentages(in: defaults), [20, 22])
  }

  func testPercentagesIgnoreValueOutOfRange() {
    defaults.set(0, forKey: TipSettings.percentageKeys[1])

    XCTAssertEqual(TipSettings.percentages(in: defaults), [18, 20, 22])
  }

  func testPercentagesIgnoreValueOfWrongType() {
    defaults.set("twenty", forKey: TipSettings.percentageKeys[1])

    XCTAssertEqual(TipSettings.percentages(in: defaults), [18, 20, 22])
  }
}
