import XCTest

#if SWIFT_PACKAGE
  @testable import ReceiptKit
#else
  @testable import open_receipt
#endif

final class ReceiptModelContractTests: XCTestCase {
  func testDecodesReceiptResponse() throws {
    let receipt = try ReceiptModelContract.receipt(from: responseData())

    XCTAssertEqual(receipt.merchantName, "Target")
    XCTAssertEqual(receipt.currency, "USD")
    XCTAssertEqual(receipt.total, 77.19)
    XCTAssertEqual(receipt.items.count, 2)
    XCTAssertEqual(receipt.payment?.last4, "1067")
  }

  func testEncodedResponseDecodesToSameReceipt() throws {
    let response = try JSONDecoder().decode(
      ReceiptModelContract.Response.self, from: responseData())
    let receipt = try ReceiptModelContract.receipt(from: JSONEncoder().encode(response))

    XCTAssertEqual(receipt.merchantName, "Target")
    XCTAssertEqual(receipt.total, 77.19)
    XCTAssertEqual(receipt.items.count, 2)
    XCTAssertEqual(receipt.payment?.authCode, "111121")
  }

  func testEncodedResponseWithoutPaymentDecodes() throws {
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: responseData()) as? [String: Any])
    object["payment"] = nil
    let response = try JSONDecoder().decode(
      ReceiptModelContract.Response.self,
      from: JSONSerialization.data(withJSONObject: object))
    let receipt = try ReceiptModelContract.receipt(from: JSONEncoder().encode(response))

    XCTAssertNil(receipt.payment)
  }

  func testInstructionsKeepAdjustmentLabelsInTheItemSection() {
    XCTAssertTrue(
      ReceiptModelContract.instructions.contains(
        "Never move a tax-labeled row from before the subtotal into taxComponents."
      ))
  }

  func testInstructionsLimitTaxComponentsToTheSummary() {
    XCTAssertTrue(
      ReceiptModelContract.instructions.contains(
        "TaxComponents contains only tax lines printed in the receipt summary after the subtotal."
      ))
  }

  func testInstructionsRecheckItemRowsAgainstPrintedSubtotal() {
    XCTAssertTrue(
      ReceiptModelContract.instructions.contains(
        "If they do not reconcile, recheck the item section for omitted or duplicated rows."))
  }

  func testInstructionsMergeProductDetailRows() {
    XCTAssertTrue(
      ReceiptModelContract.instructions.contains(
        "Do not return them as separate items."))
  }

  func testInstructionsExcludeZeroAndSavingsRows() {
    XCTAssertTrue(
      ReceiptModelContract.instructions.contains(
        "Do not return zero-value rows or discount and savings rows as items."))
  }

  func testValidatorReportsInconsistentTotals() throws {
    let receipt = try ReceiptModelContract.receipt(from: responseData(total: 80))

    XCTAssertTrue(
      receipt.warnings.contains(
        "Subtotal, tax, tip, and savings do not reconcile with the final total."))
  }

  func testValidatorUsesNormalizedSavingsInTotal() throws {
    let receipt = try ReceiptModelContract.receipt(
      from: responseData(total: 76.30, savings: -0.89))

    XCTAssertFalse(
      receipt.warnings.contains(
        "Subtotal, tax, tip, and savings do not reconcile with the final total."))
  }

  func testValidatorAcceptsSubtotalAfterSavings() throws {
    let receipt = try ReceiptModelContract.receipt(
      from: responseData(total: 77.19, savings: 0.89))

    XCTAssertFalse(
      receipt.warnings.contains(
        "Subtotal, tax, tip, and savings do not reconcile with the final total."))
  }

  func testKeepsPositivePrintedSavings() throws {
    let receipt = try ReceiptModelContract.receipt(from: responseData(savings: 0.89))

    XCTAssertEqual(receipt.savings, 0.89)
  }

  func testNormalizesNegativePrintedSavings() throws {
    let receipt = try ReceiptModelContract.receipt(from: responseData(savings: -0.89))

    XCTAssertEqual(receipt.savings, 0.89)
  }

  func testAddsPrintedTaxComponents() throws {
    let receipt = try ReceiptModelContract.receipt(
      from: responseData(taxAmounts: [0.51, 7.11, 0.40, 0.10]))

    XCTAssertEqual(receipt.tax, 8.12, accuracy: 0.000_1)
  }

  private func responseData(
    total: Double = 77.19,
    savings: Double = 0,
    taxAmounts: [Double] = [3.26]
  ) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "merchantName": " Target ",
      "date": "2026-04-11",
      "subtotal": 73.93,
      "taxComponents": taxAmounts.map { ["label": "Tax", "amount": $0] },
      "tip": 0,
      "savings": savings,
      "total": total,
      "currency": "usd",
      "payment": ["method": "VISA", "last4": "1067", "authCode": "111121"],
      "items": [
        ["description": "Diet Coke", "quantity": 1, "lineTotal": 8.89],
        ["description": "GG Sauce", "quantity": 1, "lineTotal": 3.29],
      ],
    ])
  }
}
