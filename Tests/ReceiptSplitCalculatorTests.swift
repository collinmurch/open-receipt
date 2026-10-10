import XCTest

@testable import open_receipt

@MainActor
final class ReceiptSplitCalculatorTests: XCTestCase {
  func testSharedItemIsDividedBetweenAssignedPeople() throws {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 10)
    let secondPerson = draft.addManualParticipant(named: "Sam")
    let currentUserID = try XCTUnwrap(draft.participants.first?.id)
    draft.items[0].participantIDs = [currentUserID, secondPerson.id]

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares[0].total, 5)
    XCTAssertEqual(calculation.participantShares[1].total, 5)
    XCTAssertEqual(calculation.participantShares[0].items[0].fraction, 0.5)
  }

  func testProportionalAdjustmentsFollowItemSubtotals() throws {
    let draft = try makeTwoPersonDraft()

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares[0].total, 12)
    XCTAssertEqual(calculation.participantShares[1].total, 36)
  }

  func testEvenAdjustmentsKeepItemsAssigned() throws {
    let draft = try makeTwoPersonDraft()

    let calculation = calculate(draft, .even)

    XCTAssertEqual(calculation.participantShares[0].total, 14)
    XCTAssertEqual(calculation.participantShares[1].total, 34)
  }

  func testRoundingKeepsCalculatedTotalExact() throws {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 11)
    draft.tax = 1
    let secondPerson = draft.addManualParticipant(named: "Sam")
    let thirdPerson = draft.addManualParticipant(named: "Alex")
    let currentUserID = try XCTUnwrap(draft.participants.first?.id)
    draft.items[0].participantIDs = [currentUserID, secondPerson.id, thirdPerson.id]

    let calculation = calculate(draft, .even)

    let assignedTotal = calculation.participantShares.reduce(0) { $0 + $1.total }
    XCTAssertEqual(assignedTotal, 11, accuracy: 0.000_1)
  }

  func testEvenlySharedReceiptKeepsTotalsWithinOneCent() throws {
    let draft = makeDraft(
      items: [
        ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10),
        ReceiptItem(description: "Salad", quantity: 1, lineTotal: 10),
      ],
      total: 23.50)
    draft.tax = 1
    draft.tip = 2.50
    let everyone = try assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .proportional)

    let totals = calculation.participantShares.map(\.total)
    XCTAssertEqual(everyone.count, 3)
    XCTAssertEqual(totals.max()! - totals.min()!, 0.01, accuracy: 0.000_1)
  }

  func testLeftoverCentsRotateAcrossItems() throws {
    let draft = makeDraft(
      items: [
        ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10),
        ReceiptItem(description: "Salad", quantity: 1, lineTotal: 10),
      ],
      total: 20)
    try assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares.map { $0.items[0].amount }, [3.34, 3.33, 3.33])
    XCTAssertEqual(calculation.participantShares.map { $0.items[1].amount }, [3.33, 3.34, 3.33])
  }

  func testEvenSplitOfEvenTotalIsExactlyEqual() throws {
    let draft = makeDraft(
      items: [
        ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10),
        ReceiptItem(description: "Salad", quantity: 1, lineTotal: 10),
      ],
      total: 22.50)
    draft.tax = 2.50
    try assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .even)

    XCTAssertEqual(calculation.participantShares.map(\.total), [7.50, 7.50, 7.50])
  }

  func testSharesAddUpToTotalWithFractionalCentTip() throws {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 47.37)], total: 56)
    draft.tip = 8.5266
    try assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .proportional)

    let assignedTotal = calculation.participantShares.reduce(0) { $0 + $1.total }
    XCTAssertEqual(assignedTotal, 56, accuracy: 0.000_1)
  }

  func testEveryShareIsWholeCents() throws {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 47.37)], total: 56)
    draft.tip = 8.5266
    try assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .proportional)

    for share in calculation.participantShares {
      for amount in share.items.map(\.amount) + share.adjustments.map(\.amount) {
        XCTAssertEqual(amount * 100, (amount * 100).rounded(), accuracy: 0.000_1)
      }
    }
  }

  func testProportionalSplitWithoutItemValueSharesAdjustmentsEvenly() throws {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Cover", quantity: 1, lineTotal: 0)], total: 6)
    draft.tax = 6
    let secondPerson = draft.addManualParticipant(named: "Sam")
    let currentUserID = try XCTUnwrap(draft.participants.first?.id)
    draft.items[0].participantIDs = [currentUserID, secondPerson.id]

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares.map(\.total), [3, 3])
  }

  func testSplitUsesWholeYen() throws {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Ramen", quantity: 1, lineTotal: 1000)],
      total: 1000,
      currency: "JPY")
    try assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares.map(\.total), [334, 333, 333])
  }

  func testSplitUsesThreeDecimalDinars() throws {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Tea", quantity: 1, lineTotal: 1)],
      total: 1,
      currency: "KWD")
    try assignEveryItemToThreePeople(draft)

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares.map(\.total), [0.334, 0.333, 0.333])
  }

  func testSavingsReduceParticipantTotals() throws {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 8)
    draft.savings = 2
    let currentUserID = try XCTUnwrap(draft.participants.first?.id)
    draft.items[0].participantIDs = [currentUserID]

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.participantShares[0].total, 8)
    XCTAssertEqual(calculation.participantShares[0].adjustments[0].amount, -2)
  }

  func testUnassignedItemsAreReported() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 10)

    let calculation = calculate(draft, .proportional)

    XCTAssertEqual(calculation.unassignedItemCount, 1)
  }

  func testDraftSplitCalculationUpdatesAfterItemAssignmentChanges() throws {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 10)
    let currentUserID = try XCTUnwrap(draft.participants.first?.id)

    XCTAssertEqual(draft.splitCalculation.unassignedItemCount, 1)

    draft.items[0].participantIDs = [currentUserID]

    XCTAssertEqual(draft.splitCalculation.unassignedItemCount, 0)
    XCTAssertEqual(draft.splitCalculation.participantShares[0].total, 10)
  }

  func testDraftSplitCalculationUpdatesAfterSplitMethodChanges() throws {
    let draft = try makeTwoPersonDraft()

    XCTAssertEqual(draft.splitCalculation.participantShares[0].total, 12)

    draft.adjustmentSplitMethod = .even

    XCTAssertEqual(draft.splitCalculation.participantShares[0].total, 14)
  }

  func testDraftSplitCalculationUpdatesAfterCurrencyChanges() throws {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10.5)], total: 10.5)
    let currentUserID = try XCTUnwrap(draft.participants.first?.id)
    draft.items[0].participantIDs = [currentUserID]
    XCTAssertEqual(draft.splitCalculation.participantShares[0].total, 10.5)

    draft.currency = "JPY"

    XCTAssertEqual(draft.splitCalculation.participantShares[0].total, 11)
  }

  private func makeTwoPersonDraft() throws -> ReceiptDraft {
    let draft = makeDraft(
      items: [
        ReceiptItem(description: "Coffee", quantity: 1, lineTotal: 10),
        ReceiptItem(description: "Breakfast", quantity: 1, lineTotal: 30),
      ],
      total: 48)
    draft.tax = 4
    draft.tip = 4
    let secondPerson = draft.addManualParticipant(named: "Sam")
    let currentUserID = try XCTUnwrap(draft.participants.first?.id)
    draft.items[0].participantIDs = [currentUserID]
    draft.items[1].participantIDs = [secondPerson.id]
    return draft
  }

  @discardableResult
  private func assignEveryItemToThreePeople(
    _ draft: ReceiptDraft
  ) throws -> Set<ReceiptParticipant.ID> {
    let currentUserID = try XCTUnwrap(draft.participants.first?.id)
    let sam = draft.addManualParticipant(named: "Sam")
    let alex = draft.addManualParticipant(named: "Alex")
    let everyone: Set = [currentUserID, sam.id, alex.id]
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
    total: Double,
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
