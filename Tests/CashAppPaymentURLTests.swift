import XCTest

@testable import open_receipt

final class CashAppPaymentURLTests: XCTestCase {
  func testBuildsCashAppPaymentLink() throws {
    let url = try XCTUnwrap(CashAppPaymentURL.make(cashtag: "SomeCashtag", amount: 12.5))

    XCTAssertEqual(url.absoluteString, "https://cash.app/$SomeCashtag/12.50")
  }

  func testNormalizesLeadingDollarSign() throws {
    let url = try XCTUnwrap(CashAppPaymentURL.make(cashtag: " $$sam-123 ", amount: 2))

    XCTAssertEqual(url.absoluteString, "https://cash.app/$sam-123/2.00")
  }

  func testRejectsEmptyCashtag() {
    XCTAssertNil(CashAppPaymentURL.make(cashtag: " $ ", amount: 12.5))
  }

  func testRejectsUnsafeCashtagPath() {
    XCTAssertNil(CashAppPaymentURL.make(cashtag: "sam/other", amount: 12.5))
  }

  func testRejectsZeroAmount() {
    XCTAssertNil(CashAppPaymentURL.make(cashtag: "sam", amount: 0))
  }

  func testRejectsNonfiniteAmount() {
    XCTAssertNil(CashAppPaymentURL.make(cashtag: "sam", amount: .infinity))
  }
}
