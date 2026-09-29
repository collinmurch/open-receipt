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

    let calculation = ReceiptSplitCalculator.calculate(
      draft: draft, adjustmentMethod: .proportional)

    XCTAssertEqual(calculation.participantShares[0].total, 5)
    XCTAssertEqual(calculation.participantShares[1].total, 5)
    XCTAssertEqual(calculation.participantShares[0].items[0].fraction, 0.5)
  }

  func testProportionalAdjustmentsFollowItemSubtotals() throws {
    let draft = try makeTwoPersonDraft()

    let calculation = ReceiptSplitCalculator.calculate(
      draft: draft, adjustmentMethod: .proportional)

    XCTAssertEqual(calculation.participantShares[0].total, 12)
    XCTAssertEqual(calculation.participantShares[1].total, 36)
  }

  func testEvenAdjustmentsKeepItemsAssigned() throws {
    let draft = try makeTwoPersonDraft()

    let calculation = ReceiptSplitCalculator.calculate(
      draft: draft, adjustmentMethod: .even)

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

    let calculation = ReceiptSplitCalculator.calculate(
      draft: draft, adjustmentMethod: .even)

    let assignedTotal = calculation.participantShares.reduce(0) { $0 + $1.total }
    XCTAssertEqual(assignedTotal, 11, accuracy: 0.000_1)
  }

  func testSavingsReduceParticipantTotals() throws {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 8)
    draft.savings = 2
    let currentUserID = try XCTUnwrap(draft.participants.first?.id)
    draft.items[0].participantIDs = [currentUserID]

    let calculation = ReceiptSplitCalculator.calculate(
      draft: draft, adjustmentMethod: .proportional)

    XCTAssertEqual(calculation.participantShares[0].total, 8)
    XCTAssertEqual(calculation.participantShares[0].adjustments[0].amount, -2)
  }

  func testUnassignedItemsAreReported() {
    let draft = makeDraft(
      items: [ReceiptItem(description: "Pizza", quantity: 1, lineTotal: 10)], total: 10)

    let calculation = ReceiptSplitCalculator.calculate(
      draft: draft, adjustmentMethod: .proportional)

    XCTAssertEqual(calculation.unassignedItemCount, 1)
    XCTAssertEqual(calculation.unassignedItemTotal, 10)
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

  private func makeDraft(items: [ReceiptItem], total: Double) -> ReceiptDraft {
    ReceiptDraft(
      receipt: ParsedReceipt(
        merchantName: "Cafe",
        subtotal: items.reduce(0) { $0 + $1.lineTotal },
        total: total,
        items: items))
  }
}
