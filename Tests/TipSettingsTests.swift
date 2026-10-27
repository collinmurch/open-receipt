import XCTest

@testable import open_receipt

final class TipSettingsTests: XCTestCase {
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = isolatedDefaults()
  }

  func testBaseStartsBeforeTax() {
    XCTAssertEqual(TipSettings.base(in: defaults), .beforeTax)
  }

  func testBaseUsesStoredChoice() {
    defaults.set(TipBase.afterTax.rawValue, forKey: TipSettings.baseKey)

    XCTAssertEqual(TipSettings.base(in: defaults), .afterTax)
  }

  func testBaseIgnoresUnknownChoice() {
    defaults.set("withTip", forKey: TipSettings.baseKey)

    XCTAssertEqual(TipSettings.base(in: defaults), .beforeTax)
  }

  func testCaptionSaysPercentageOfBase() {
    let caption = TipBaseCaption.text(
      tip: 8.94, base: 44.70, isAfterTax: false, currencyCode: "USD")

    XCTAssertEqual(caption, "20% of $44.70 before tax")
  }

  func testCaptionNamesAfterTaxBase() {
    let caption = TipBaseCaption.text(
      tip: 10, base: 50, isAfterTax: true, currencyCode: "USD")

    XCTAssertEqual(caption, "20% of $50.00 after tax")
  }

  func testCaptionShowsTenthsOfPercent() {
    let caption = TipBaseCaption.text(
      tip: 9.25, base: 50, isAfterTax: false, currencyCode: "USD")

    XCTAssertEqual(caption, "18.5% of $50.00 before tax")
  }

  func testCaptionNamesSavingsStillToComeOff() {
    let caption = TipBaseCaption.text(
      tip: 10, base: 50, isAfterTax: false, isAfterSavings: false, currencyCode: "USD")

    XCTAssertEqual(caption, "20% of $50.00 before tax and savings")
  }

  func testCaptionNamesSavingsAlreadyTakenOff() {
    let caption = TipBaseCaption.text(
      tip: 10, base: 50, isAfterTax: false, isAfterSavings: true, currencyCode: "USD")

    XCTAssertEqual(caption, "20% of $50.00 after savings, before tax")
  }

  func testCaptionNamesSavingsAfterTax() {
    let caption = TipBaseCaption.text(
      tip: 10, base: 50, isAfterTax: true, isAfterSavings: true, currencyCode: "USD")

    XCTAssertEqual(caption, "20% of $50.00 after tax and savings")
  }

  func testNoCaptionWithoutTip() {
    XCTAssertNil(
      TipBaseCaption.text(tip: 0, base: 50, isAfterTax: false, currencyCode: "USD"))
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
