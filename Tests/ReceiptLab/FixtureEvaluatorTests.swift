import ReceiptKit
import XCTest

@testable import ReceiptLab

final class FixtureEvaluatorTests: XCTestCase {
  func testAcceptsMinorOCRDriftWhenAmountMatches() throws {
    let evaluation = FixtureEvaluator.evaluate(
      actual: ParsedReceipt(
        items: [ReceiptItem(description: "JFRGDN BANANA FRR RINGS", quantity: 1, lineTotal: 3.99)]),
      expected: ExpectedReceipt(
        items: [ExpectedItem(rawName: "JFGRDN BANANA PPR RINGS", lineTotal: 3.99)]))

    let check = try XCTUnwrap(evaluation.checks.first { $0.field == "items[0].name" })
    XCTAssertEqual(check.status, .pass)
  }

  func testRejectsUnrelatedNameWhenAmountMatches() throws {
    let evaluation = FixtureEvaluator.evaluate(
      actual: ParsedReceipt(
        items: [ReceiptItem(description: "DISH SOAP", quantity: 1, lineTotal: 3.99)]),
      expected: ExpectedReceipt(
        items: [ExpectedItem(rawName: "JFGRDN BANANA PPR RINGS", lineTotal: 3.99)]))

    let check = try XCTUnwrap(evaluation.checks.first { $0.field == "items[0].name" })
    XCTAssertEqual(check.status, .fail)
  }

  func testRequiresExactItemCountWithoutDetailedItems() throws {
    let evaluation = FixtureEvaluator.evaluate(
      actual: ParsedReceipt(
        items: [ReceiptItem(description: "BANANA", quantity: 1, lineTotal: 1.08)]),
      expected: ExpectedReceipt(itemCount: 3))

    let check = try XCTUnwrap(evaluation.checks.first { $0.field == "itemCount" })
    XCTAssertEqual(check.status, .fail)
    XCTAssertEqual(check.detail, "Δ -2")
  }

  func testAcceptsDerivedUnitPriceWithinTolerance() throws {
    let evaluation = FixtureEvaluator.evaluate(
      actual: ParsedReceipt(
        items: [ReceiptItem(description: "BANANAS", quantity: 2, lineTotal: 3.00)]),
      expected: ExpectedReceipt(
        amountTolerance: 0.01,
        items: [
          ExpectedItem(rawName: "BANANAS", lineTotal: 3.00, unitPrice: 1.50)
        ]))

    let check = try XCTUnwrap(evaluation.checks.first { $0.field == "items[0].unitPrice" })
    XCTAssertEqual(check.status, .pass)
  }

  func testRejectsIncorrectDerivedUnitPrice() throws {
    let evaluation = FixtureEvaluator.evaluate(
      actual: ParsedReceipt(
        items: [ReceiptItem(description: "BANANAS", quantity: 2, lineTotal: 3.00)]),
      expected: ExpectedReceipt(
        amountTolerance: 0.01,
        items: [
          ExpectedItem(rawName: "BANANAS", lineTotal: 3.00, unitPrice: 1.25)
        ]))

    let check = try XCTUnwrap(evaluation.checks.first { $0.field == "items[0].unitPrice" })
    XCTAssertEqual(check.status, .fail)
  }

  func testExplicitEmptyItemsRejectsParsedItems() throws {
    let evaluation = FixtureEvaluator.evaluate(
      actual: ParsedReceipt(
        items: [ReceiptItem(description: "BANANAS", quantity: 1, lineTotal: 1.50)]),
      expected: ExpectedReceipt(items: []))

    let summary = try XCTUnwrap(evaluation.checks.first { $0.field == "itemAmounts" })
    let extra = try XCTUnwrap(evaluation.checks.first { $0.field == "items.extra[0]" })
    XCTAssertEqual(summary.status, .fail)
    XCTAssertEqual(extra.status, .fail)
  }
}
