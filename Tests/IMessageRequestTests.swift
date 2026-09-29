import XCTest

@testable import open_receipt

final class IMessageRequestTests: XCTestCase {
  func testBuildsMessageWithAmountAndContext() throws {
    let body = try XCTUnwrap(
      IMessageRequest.body(amount: 12.5, currency: "USD", context: "Receipt split: Cafe"))

    XCTAssertEqual(body, "Could you send me $12.50 with Apple Cash? Receipt split: Cafe")
  }

  func testBuildsMessageWithoutContext() throws {
    let body = try XCTUnwrap(
      IMessageRequest.body(amount: 12.5, currency: "USD", context: "  "))

    XCTAssertEqual(body, "Could you send me $12.50 with Apple Cash?")
  }

  func testRejectsZeroAmount() {
    XCTAssertNil(IMessageRequest.body(amount: 0, currency: "USD", context: "Receipt split"))
  }

  func testRejectsInvalidCurrency() {
    XCTAssertNil(IMessageRequest.body(amount: 12.5, currency: "US", context: "Receipt split"))
  }
}
