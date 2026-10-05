import XCTest

@testable import open_receipt

final class VenmoRequestURLTests: XCTestCase {
  func testBuildsChargeRequest() throws {
    let url = try XCTUnwrap(
      VenmoRequestURL.make(
        recipient: recipient(.username, "sam"), amount: 12.34, note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(components.scheme, "venmo")
    XCTAssertEqual(components.host, "paycharge")
    XCTAssertEqual(queryValue("txn", in: components), "charge")
  }

  func testIncludesRecipient() throws {
    let url = try XCTUnwrap(
      VenmoRequestURL.make(
        recipient: recipient(.username, "sam"), amount: 12.34, note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("recipients", in: components), "sam")
  }

  func testNormalizesRecipient() throws {
    let url = try XCTUnwrap(
      VenmoRequestURL.make(
        recipient: recipient(.username, "  @sam  "), amount: 12.34, note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("recipients", in: components), "sam")
  }

  func testIncludesPhoneNumberRecipient() throws {
    let url = try XCTUnwrap(
      VenmoRequestURL.make(
        recipient: recipient(.phoneNumber, "+1 646-863-9557"),
        amount: 12.34,
        note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("recipients", in: components), "6468639557")
  }

  func testNormalizesTenDigitPhoneNumberRecipient() throws {
    let url = try XCTUnwrap(
      VenmoRequestURL.make(
        recipient: recipient(.phoneNumber, "(646) 863-9557"),
        amount: 12.34,
        note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("recipients", in: components), "6468639557")
  }

  func testRejectsPhoneNumberWithoutTenUSDigits() {
    XCTAssertNil(
      VenmoRequestURL.make(
        recipient: recipient(.phoneNumber, "+44 20 7946 0958"),
        amount: 12.34,
        note: "Receipt split"))
  }

  func testIncludesEmailAddressRecipient() throws {
    let url = try XCTUnwrap(
      VenmoRequestURL.make(
        recipient: recipient(.emailAddress, "sam@example.com"),
        amount: 12.34,
        note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("recipients", in: components), "sam@example.com")
  }

  func testFormatsAmountWithTwoDecimalPlaces() throws {
    let url = try XCTUnwrap(
      VenmoRequestURL.make(
        recipient: recipient(.username, "sam"), amount: 12.3, note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("amount", in: components), "12.30")
  }

  func testEncodesNote() throws {
    let url = try XCTUnwrap(
      VenmoRequestURL.make(
        recipient: recipient(.username, "sam"), amount: 12.34, note: "Cafe & Bakery"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("note", in: components), "Cafe & Bakery")
  }

  func testRejectsEmptyRecipient() {
    XCTAssertNil(
      VenmoRequestURL.make(
        recipient: recipient(.username, " @ "), amount: 12.34, note: "Receipt split"))
  }

  func testRejectsZeroAmount() {
    XCTAssertNil(
      VenmoRequestURL.make(
        recipient: recipient(.username, "sam"), amount: 0, note: "Receipt split"))
  }

  func testRejectsNonfiniteAmount() {
    XCTAssertNil(
      VenmoRequestURL.make(
        recipient: recipient(.username, "sam"),
        amount: .infinity,
        note: "Receipt split"))
  }

  private func recipient(
    _ kind: Person.Venmo.Recipient.Kind,
    _ value: String
  ) -> Person.Venmo.Recipient {
    .init(kind: kind, value: value)
  }

  private func queryValue(_ name: String, in components: URLComponents) -> String? {
    components.queryItems?.first { $0.name == name }?.value
  }
}
