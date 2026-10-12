import SwiftUI
import XCTest

@testable import open_receipt

@MainActor
final class AdjustmentChoiceTests: XCTestCase {
  private let presets = [
    AdjustmentPreset(title: "18%", amount: 1.80),
    AdjustmentPreset(title: "20%", amount: 2),
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

  func testAmountMatchingPresetChoosesIt() {
    let choice = makeChoice(amount: 2)

    XCTAssertEqual(choice.wrappedValue, .preset(presets[1]))
  }

  func testAmountMatchingNoPresetIsCustom() {
    let choice = makeChoice(amount: 3)

    XCTAssertEqual(choice.wrappedValue, .custom)
  }

  func testChosenCustomStaysCustomAtPresetAmount() {
    let choice = makeChoice(amount: 2, isCustom: true)

    XCTAssertEqual(choice.wrappedValue, .custom)
  }

  func testChoosingPresetSetsAmount() {
    var amount = 3.0
    let choice = makeChoice(amount: Binding(get: { amount }, set: { amount = $0 }))

    choice.wrappedValue = .preset(presets[0])

    XCTAssertEqual(amount, 1.80)
  }

  func testChoosingPresetEndsCustom() {
    var isCustom = true
    let choice = makeChoice(
      amount: .constant(3), isCustom: Binding(get: { isCustom }, set: { isCustom = $0 }))

    choice.wrappedValue = .preset(presets[0])

    XCTAssertFalse(isCustom)
  }

  func testChoosingCustomKeepsAmount() {
    var amount = 2.0
    let choice = makeChoice(amount: Binding(get: { amount }, set: { amount = $0 }))

    choice.wrappedValue = .custom

    XCTAssertEqual(amount, 2)
    XCTAssertEqual(choice.wrappedValue, .custom)
  }

  private func makeChoice(amount: Double, isCustom: Bool = false) -> Binding<AdjustmentChoice> {
    makeChoice(amount: .constant(amount), isCustom: .constant(isCustom))
  }

  private func makeChoice(
    amount: Binding<Double>,
    isCustom: Binding<Bool>? = nil
  ) -> Binding<AdjustmentChoice> {
    var storedIsCustom = false
    return AdjustmentChoice.binding(
      amount: amount,
      isCustom: isCustom ?? Binding(get: { storedIsCustom }, set: { storedIsCustom = $0 }),
      presets: presets)
  }
}
