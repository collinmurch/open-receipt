import XCTest

@testable import open_receipt

@MainActor
final class AdjustmentChoiceTests: XCTestCase {
  private let presets = [
    AdjustmentPreset(title: "18%", amount: 1.80, percentage: 18),
    AdjustmentPreset(title: "20%", amount: 2, percentage: 20),
  ]

  func testPercentagePresetRoundsToCurrency() {
    let preset = AdjustmentPreset.percentage(18, of: 42.10, currencyCode: "USD")

    XCTAssertEqual(preset.amount, 7.58)
  }

  func testPercentagePresetRoundsToWholeYen() {
    let preset = AdjustmentPreset.percentage(18, of: 1015, currencyCode: "JPY")

    XCTAssertEqual(preset.amount, 183)
  }

  func testPercentagePresetIsTitledWithPercentage() {
    let preset = AdjustmentPreset.percentage(18, of: 10, currencyCode: "USD")

    XCTAssertEqual(preset.title, 18.0.formatted(.percent.scale(1)))
  }

  func testMiddlePresetOfThreeIsSecond() {
    let presets = presets + [AdjustmentPreset(title: "22%", amount: 2.20)]

    XCTAssertEqual(presets.middle?.title, "20%")
  }

  func testNoMiddlePresetWhenEmpty() {
    XCTAssertNil([AdjustmentPreset]().middle)
  }

  func testPercentageChoosesItsPreset() {
    let choice = AdjustmentChoice(percentage: 20, presets: presets)

    XCTAssertEqual(choice, .preset(presets[1]))
  }

  func testPercentageChoosesItsPresetAmongPresetsOfOneAmount() {
    let presets = [18, 20, 22].map {
      AdjustmentPreset.percentage($0, of: 0.05, currencyCode: "USD")
    }

    let choice = AdjustmentChoice(percentage: 22, presets: presets)

    XCTAssertEqual(choice.percentage, 22)
  }

  func testNoPercentageIsCustom() {
    XCTAssertEqual(AdjustmentChoice(percentage: nil, presets: presets), .custom)
  }

  func testPercentageWithoutPresetIsCustom() {
    XCTAssertEqual(AdjustmentChoice(percentage: 25, presets: presets), .custom)
  }

  func testCustomHasNoPercentage() {
    XCTAssertNil(AdjustmentChoice.custom.percentage)
  }

  func testPresetWithoutPercentageHasNone() {
    let choice = AdjustmentChoice.preset(AdjustmentPreset(title: "Auto", amount: 1))

    XCTAssertNil(choice.percentage)
  }
}
