import XCTest

@testable import open_receipt

@MainActor
final class ReceiptSplitCalculatorTests: XCTestCase {
  func testSharedItemIsDividedBetweenAssignedPeople() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 10)
    let secondPerson = draft.addManualParticipant(named: "Sam")
    draft.items[0].participantIDs = [draft.ownerID, secondPerson.id]

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares[0].total, 5)
    XCTAssertEqual(calculation.participantShares[1].total, 5)
    XCTAssertEqual(calculation.participantShares[0].items[0].fraction, 0.5)
  }

  func testItemShareKeepsItemQuantity() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Taco", quantity: 3, lineTotal: 9)], total: 9)
    draft.items[0].participantIDs = [draft.ownerID]

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares[0].items[0].quantity, 3)
  }

  func testItemCountIncludesQuantities() {
    let draft = makeDraft(
      items: [
        ReceiptItem(description: "Taco", quantity: 2, lineTotal: 6),
        ReceiptItem(description: "Soda", quantity: 1, lineTotal: 2),
      ],
      total: 8)
    draft.items[0].participantIDs = [draft.ownerID]
    draft.items[1].participantIDs = [draft.ownerID]

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares[0].itemCount, 3)
  }

  func testWeighedItemCountsAsOneItem() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Bananas", quantity: 1.42, lineTotal: 0.85)], total: 0.85)
    draft.items[0].participantIDs = [draft.ownerID]

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares[0].itemCount, 1)
  }

  func testProportionalAdjustmentsFollowItemSubtotals() {
    let draft = makeTwoPersonDraft()

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares[0].total, 12)
    XCTAssertEqual(calculation.participantShares[1].total, 36)
  }

  func testEvenAdjustmentsKeepItemsAssigned() {
    let draft = makeTwoPersonDraft()

    let calculation = calculate(draft, .even)

    XCTAssertEqual(calculation.participantShares[0].total, 14)
    XCTAssertEqual(calculation.participantShares[1].total, 34)
  }

  func testRoundingKeepsCalculatedTotalExact() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 11)
    draft.tax = 1
    let secondPerson = draft.addManualParticipant(named: "Sam")
    let thirdPerson = draft.addManualParticipant(named: "Alex")
    draft.items[0].participantIDs = [draft.ownerID, secondPerson.id, thirdPerson.id]

    let calculation = calculate(draft, .even)

    let assignedTotal = calculation.participantShares.reduce(0) { $0 + $1.total }
    XCTAssertEqual(assignedTotal, 11)
  }

  func testEvenlySharedReceiptKeepsTotalsWithinOneCent() {
    let draft = makeDraft(
      items: [
        ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10),
        ReceiptItem(description: "Salad", quantity: 1, lineTotal: 10),
      ],
      total: 23.50)
    draft.tax = 1
    draft.tip = 2.50
    let everyone = assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .proportional)

    let totals = calculation.participantShares.map(\.total)
    XCTAssertEqual(everyone.count, 3)
    XCTAssertEqual(totals.max()! - totals.min()!, 0.01)
  }

  func testLeftoverCentsGoToDifferentPeopleAcrossItems() {
    let draft = makeDraft(
      items: [
        ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10),
        ReceiptItem(description: "Salad", quantity: 1, lineTotal: 10),
      ],
      total: 20)
    assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares.map { $0.items[0].amount }, [3.33, 3.34, 3.33])
    XCTAssertEqual(calculation.participantShares.map { $0.items[1].amount }, [3.33, 3.33, 3.34])
  }

  func testOwnerPaysLessOfTiedLeftoverCharge() {
    let draft = makeThreePersonDraftWithOwnItems(total: 31)
    draft.tax = 1

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares.map(\.total), [10.33, 10.34, 10.33])
  }

  func testOwnerTakesTiedLeftoverSaving() {
    let draft = makeThreePersonDraftWithOwnItems(total: 29)
    draft.savings = 1

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares.map(\.total), [9.66, 9.67, 9.67])
  }

  func testOwnerPaysLessOfTiedLeftoverWhenListedLast() {
    let draft = makeThreePersonDraftWithOwnItems(total: 31)
    draft.tax = 1
    var input = draft.splitInput
    input.participants.reverse()

    let calculation = ReceiptSplitCalculator.calculate(input)

    XCTAssertEqual(calculation.participantShares.map(\.total), [10.34, 10.33, 10.33])
  }

  func testTiedLeftoverGoesToFirstPersonWithoutOwner() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 11)
    draft.tax = 1
    let people = ["Sam", "Alex", "Jo"].map { draft.addManualParticipant(named: $0).id }
    draft.items[0].participantIDs = Set(people)
    var input = draft.splitInput
    input.participants.removeFirst()

    let calculation = ReceiptSplitCalculator.calculate(input)

    XCTAssertEqual(calculation.participantShares.map(\.total), [3.67, 3.67, 3.66])
  }

  func testOwnerIsRoundedUpLastEvenWithLargerLeftover() {
    let draft = makeDraft(
      items: [
        ReceiptItem(description: "Fries", quantity: 1, lineTotal: 0.01),
        ReceiptItem(description: "Chips", quantity: 1, lineTotal: 0.01),
        ReceiptItem(description: "Mints", quantity: 1, lineTotal: 0.01),
      ],
      total: 0.03)
    let sam = draft.addManualParticipant(named: "Sam")
    let alex = draft.addManualParticipant(named: "Alex")
    draft.items[0].participantIDs = [draft.ownerID, sam.id]
    draft.items[1].participantIDs = [draft.ownerID, sam.id, alex.id]
    draft.items[2].participantIDs = [sam.id, alex.id]

    let calculation = calculate(draft, .even)

    XCTAssertEqual(calculation.participantShares.map(\.total), [0, 0.02, 0.01])
  }

  func testRandomEvenTotalsStayWithinOneCentOfExactShare() {
    for seed in 0..<200 {
      var generator = SeededGenerator(seed: UInt64(seed))
      let draft = makeRandomDraft(using: &generator)

      let calculation = calculate(draft, .even)

      let adjustmentShareCents = adjustmentCents(of: draft) / Double(draft.participants.count)
      for share in calculation.participantShares {
        let exact = exactItemCents(of: share, in: draft) + adjustmentShareCents
        XCTAssertEqual(Double(units(share.total)), exact, accuracy: 1.000_1, "seed \(seed)")
      }
    }
  }

  func testRandomProportionalTotalsStayWithinOneCentOfExactShare() {
    for seed in 0..<200 {
      var generator = SeededGenerator(seed: UInt64(seed))
      let draft = makeRandomDraft(using: &generator)

      let calculation = calculate(draft, .proportional)

      let itemCents = calculation.participantShares.map { exactItemCents(of: $0, in: draft) }
      let itemTotalCents = itemCents.reduce(0, +)
      for (share, items) in zip(calculation.participantShares, itemCents) {
        let exact = items + adjustmentCents(of: draft) * items / itemTotalCents
        XCTAssertEqual(Double(units(share.total)), exact, accuracy: 1.000_1, "seed \(seed)")
      }
    }
  }

  func testRandomSharesAddUpToTotal() {
    for seed in 0..<200 {
      var generator = SeededGenerator(seed: UInt64(seed))
      let draft = makeRandomDraft(using: &generator)

      let calculation = calculate(draft, .proportional)

      let assignedTotal = calculation.participantShares.reduce(0) { $0 + $1.total }
      XCTAssertEqual(assignedTotal, draft.total, "seed \(seed)")
    }
  }

  func testRandomItemSharesAddUpToEachItem() {
    for seed in 0..<200 {
      var generator = SeededGenerator(seed: UInt64(seed))
      let draft = makeRandomDraft(using: &generator)

      let calculation = calculate(draft, .even)

      for item in draft.items {
        let shared = calculation.participantShares.flatMap(\.items)
          .filter { $0.itemID == item.id }
          .reduce(0) { $0 + $1.amount }
        XCTAssertEqual(shared, item.lineTotal, "seed \(seed)")
      }
    }
  }

  func testRandomAdjustmentSharesAddUpToEachAdjustment() {
    for seed in 0..<200 {
      var generator = SeededGenerator(seed: UInt64(seed))
      let draft = makeRandomDraft(using: &generator)

      let calculation = calculate(draft, .proportional)

      for kind in ReceiptTotalAdjustment.allCases {
        let shared = calculation.participantShares.flatMap(\.adjustments)
          .filter { $0.id == kind.rawValue }
          .reduce(0) { $0 + $1.amount }
        XCTAssertEqual(
          shared, draft.adjustments.signedAmount(of: kind), "seed \(seed)")
      }
    }
  }

  func testRandomItemSharesStayWithinOneCentOfExactShare() {
    for seed in 0..<200 {
      var generator = SeededGenerator(seed: UInt64(seed))
      let draft = makeRandomDraft(using: &generator)

      let calculation = calculate(draft, .even)

      for share in calculation.participantShares.flatMap(\.items) {
        let exact = lineCents(of: share.itemID, in: draft) * share.fraction
        XCTAssertEqual(Double(units(share.amount)), exact, accuracy: 0.999_9, "seed \(seed)")
      }
    }
  }

  func testLargeGroupSplitsQuickly() {
    var generator = SeededGenerator(seed: 7)
    let itemCents = (0..<100).map { _ in Int.random(in: 1...5_000, using: &generator) }
    let draft = makeDraft(
      items: itemCents.enumerated().map {
        ReceiptItem(description: "Item \($0)", quantity: 1, lineTotal: cents($1))
      },
      total: cents(itemCents.reduce(0, +) + 1_234))
    draft.tax = 12.34
    let people =
      [draft.ownerID] + (1..<20).map { draft.addManualParticipant(named: "Person \($0)").id }
    for index in draft.items.indices {
      let group = people.filter { _ in Int.random(in: 0..<3, using: &generator) > 0 }
      draft.items[index].participantIDs = Set(group.isEmpty ? people : group)
    }
    let input = draft.splitInput

    let clock = ContinuousClock()
    let elapsed = (0..<3).map { _ in
      clock.measure { _ = ReceiptSplitCalculator.calculate(input) }
    }.min()!

    XCTAssertLessThan(elapsed, .milliseconds(20))
  }

  func testEvenSplitOfEvenTotalIsExactlyEqual() {
    let draft = makeDraft(
      items: [
        ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10),
        ReceiptItem(description: "Salad", quantity: 1, lineTotal: 10),
      ],
      total: 22.50)
    draft.tax = 2.50
    assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .even)

    XCTAssertEqual(calculation.participantShares.map(\.total), [7.50, 7.50, 7.50])
  }

  func testSharesAddUpToTotalWithFractionalCentTip() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 47.37)], total: 56)
    draft.tip = 8.5266
    assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .proportional)

    let assignedTotal = calculation.participantShares.reduce(0) { $0 + $1.total }
    XCTAssertEqual(assignedTotal, 56)
  }

  func testEveryShareIsWholeCents() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 47.37)], total: 56)
    draft.tip = 8.5266
    assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .proportional)

    for share in calculation.participantShares {
      for amount in share.items.map(\.amount) + share.adjustments.map(\.amount) {
        XCTAssertEqual(amount.rounded(places: 2), amount)
      }
    }
  }

  func testProportionalSplitWithoutItemValueSharesAdjustmentsEvenly() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Cover", quantity: 1, lineTotal: 0)], total: 6)
    draft.tax = 6
    let secondPerson = draft.addManualParticipant(named: "Sam")
    draft.items[0].participantIDs = [draft.ownerID, secondPerson.id]

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares.map(\.total), [3, 3])
  }

  func testSplitUsesWholeYen() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Ramen", quantity: 1, lineTotal: 1000)],
      total: 1000,
      currency: "JPY")
    assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares.map(\.total), [333, 334, 333])
  }

  func testWholeYenSplitAddsUpToRoundedTotalWhenItemsRoundApart() {
    let draft = makeDraft(
      items: ["Tea", "Rice", "Miso"].map {
        ReceiptItem(description: $0, quantity: 1, lineTotal: 0.5)
      },
      total: 1.5,
      currency: "JPY")
    assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .even)

    XCTAssertEqual(calculation.participantShares.reduce(0) { $0 + $1.total }, 2)
  }

  func testSplitUsesThreeDecimalDinars() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Tea", quantity: 1, lineTotal: 1)],
      total: 1,
      currency: "KWD")
    assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares.map(\.total), [0.333, 0.334, 0.333])
  }

  func testSavingsReduceParticipantTotals() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 8)
    draft.savings = 2
    draft.items[0].participantIDs = [draft.ownerID]

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares[0].total, 8)
    XCTAssertEqual(calculation.participantShares[0].adjustments[0].amount, -2)
  }

  func testSavingsAlreadyInItemPricesAreNotTakenOffAgain() {
    let draft = ReceiptDraft(
      receipt: ParsedReceipt(
        subtotal: 10, savings: 2, total: 10,
        items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)]))
    draft.items[0].participantIDs = [draft.ownerID]

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares[0].total, 10)
    XCTAssertTrue(calculation.participantShares[0].adjustments.isEmpty)
  }

  func testReceiptWithoutSubtotalSharesNoSubtotalAdjustment() {
    let draft = ReceiptDraft(
      receipt: ParsedReceipt(
        tax: 1, total: 11,
        items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)]))
    draft.items[0].participantIDs = [draft.ownerID]

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares[0].adjustments.map(\.id), ["tax"])
  }

  func testItemsShortOfSubtotalAreSharedAsSubtotalAdjustment() {
    let draft = ReceiptDraft(
      receipt: ParsedReceipt(
        subtotal: 12, total: 12,
        items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)]))
    draft.items[0].participantIDs = [draft.ownerID]

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares[0].adjustments.map(\.id), ["subtotal-adjustment"])
    XCTAssertEqual(calculation.participantShares[0].total, 12)
  }

  func testUnassignedItemsAreReported() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 10)

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.unassignedItemCount, 1)
  }

  func testDraftSplitCalculationUpdatesAfterItemAssignmentChanges() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 10)

    XCTAssertEqual(draft.splitCalculation.unassignedItemCount, 1)

    draft.items[0].participantIDs = [draft.ownerID]

    XCTAssertEqual(draft.splitCalculation.unassignedItemCount, 0)
    XCTAssertEqual(draft.splitCalculation.participantShares[0].total, 10)
  }

  func testDraftSplitCalculationUpdatesAfterSplitMethodChanges() {
    let draft = makeTwoPersonDraft()

    XCTAssertEqual(draft.splitCalculation.participantShares[0].total, 12)

    draft.adjustmentSplitMethod = .even

    XCTAssertEqual(draft.splitCalculation.participantShares[0].total, 14)
  }

  func testDraftSplitCalculationUpdatesAfterCurrencyChanges() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10.5)], total: 10.5)
    draft.items[0].participantIDs = [draft.ownerID]
    XCTAssertEqual(draft.splitCalculation.participantShares[0].total, 10.5)

    draft.currency = "JPY"

    XCTAssertEqual(draft.splitCalculation.participantShares[0].total, 11)
  }

  private func makeThreePersonDraftWithOwnItems(total: Money) -> ReceiptDraft {
    let draft = makeDraft(
      items: ["Pizza", "Salad", "Pasta"].map {
        ReceiptItem(description: $0, quantity: 1, lineTotal: 10)
      },
      total: total)
    let sam = draft.addManualParticipant(named: "Sam")
    let alex = draft.addManualParticipant(named: "Alex")
    draft.items[0].participantIDs = [draft.ownerID]
    draft.items[1].participantIDs = [sam.id]
    draft.items[2].participantIDs = [alex.id]
    return draft
  }

  /// A receipt for four people with random items, each shared by a random group, and random tax,
  /// tip, and savings.
  private func makeRandomDraft(using generator: inout SeededGenerator) -> ReceiptDraft {
    let itemCents = (0..<Int.random(in: 1...8, using: &generator)).map { _ in
      Int.random(in: 1...5_000, using: &generator)
    }
    let taxCents = Int.random(in: 0...999, using: &generator)
    let tipCents = Int.random(in: 0...999, using: &generator)
    let savingsCents = Int.random(in: 0...499, using: &generator)
    let draft = makeDraft(
      items: itemCents.enumerated().map {
        ReceiptItem(description: "Item \($0)", quantity: 1, lineTotal: cents($1))
      },
      total: cents(itemCents.reduce(0, +) + taxCents + tipCents - savingsCents))
    draft.tax = cents(taxCents)
    draft.tip = cents(tipCents)
    draft.savings = cents(savingsCents)
    let people =
      [draft.ownerID] + ["Sam", "Alex", "Jo"].map { draft.addManualParticipant(named: $0).id }
    for index in draft.items.indices {
      let group = people.filter { _ in Bool.random(using: &generator) }
      draft.items[index].participantIDs = Set(group.isEmpty ? [people[index % 4]] : group)
    }
    return draft
  }

  private func exactItemCents(of share: ReceiptParticipantShare, in draft: ReceiptDraft) -> Double {
    share.items.reduce(0) { $0 + lineCents(of: $1.itemID, in: draft) * $1.fraction }
  }

  private func lineCents(of itemID: ReceiptDraftItem.ID, in draft: ReceiptDraft) -> Double {
    Double(units(draft.items.first { $0.id == itemID }?.lineTotal ?? 0))
  }

  private func adjustmentCents(of draft: ReceiptDraft) -> Double {
    Double(units(draft.total - draft.itemsTotal))
  }

  private func cents(_ units: Int) -> Money {
    Money(units: units, places: 2)
  }

  private func units(_ amount: Money) -> Int {
    ReceiptCurrency.minorUnits(amount, code: "USD")
  }

  private func makeTwoPersonDraft() -> ReceiptDraft {
    let draft = makeDraft(
      items: [
        ReceiptItem(description: "Coffee", quantity: 1, lineTotal: 10),
        ReceiptItem(description: "Breakfast", quantity: 1, lineTotal: 30),
      ],
      total: 48)
    draft.tax = 4
    draft.tip = 4
    let secondPerson = draft.addManualParticipant(named: "Sam")
    draft.items[0].participantIDs = [draft.ownerID]
    draft.items[1].participantIDs = [secondPerson.id]
    return draft
  }

  @discardableResult
  private func assignEveryItemToThreePeople(
    _ draft: ReceiptDraft
  ) -> Set<ReceiptParticipant.ID> {
    let sam = draft.addManualParticipant(named: "Sam")
    let alex = draft.addManualParticipant(named: "Alex")
    let everyone: Set = [draft.ownerID, sam.id, alex.id]
    for index in draft.items.indices {
      draft.items[index].participantIDs = everyone
    }
    return everyone
  }

  private func calculate(
    _ draft: ReceiptDraft,
    _ adjustmentMethod: ReceiptAdjustmentSplitMethod
  ) -> ReceiptSplitCalculation {
    var input = draft.splitInput
    input.adjustmentMethod = adjustmentMethod
    return ReceiptSplitCalculator.calculate(input)
  }

  private func makeDraft(
    items: [ReceiptItem],
    total: Money,
    currency: String = "USD"
  ) -> ReceiptDraft {
    ReceiptDraft(
      receipt: ParsedReceipt(
        merchantName: "Cafe",
        subtotal: items.reduce(0) { $0 + $1.lineTotal },
        total: total,
        currency: currency,
        items: items))
  }
}

/// A SplitMix64 generator, so randomly built receipts are the same on every run.
private struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
