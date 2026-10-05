import XCTest

@testable import open_receipt

final class PaymentRecipientDisplayTests: XCTestCase {
  func testVenmoPhoneNumberDropsUSCountryCode() {
    let recipient = Person.Venmo.Recipient(kind: .phoneNumber, value: "1 (646) 863-9557")

    XCTAssertEqual(recipient.displayValue, "(646) 863-9557")
    XCTAssertEqual(recipient.normalizedUSPhoneNumber, "6468639557")
  }

  func testVenmoPhoneNumberDropsPlusCountryCode() {
    let recipient = Person.Venmo.Recipient(kind: .phoneNumber, value: "+1 646-863-9557")

    XCTAssertEqual(recipient.displayValue, "(646) 863-9557")
  }

  func testVenmoNonUSPhoneNumberIsUnchanged() {
    let recipient = Person.Venmo.Recipient(kind: .phoneNumber, value: "+44 20 7946 0958")

    XCTAssertEqual(recipient.displayValue, "+44 20 7946 0958")
    XCTAssertNil(recipient.normalizedUSPhoneNumber)
  }

  func testVenmoEmailHasNoPhoneNumber() {
    let recipient = Person.Venmo.Recipient(kind: .emailAddress, value: "6468639557@example.com")

    XCTAssertEqual(recipient.displayValue, "6468639557@example.com")
    XCTAssertNil(recipient.normalizedUSPhoneNumber)
  }

  func testIMessagePhoneNumberIsFormatted() {
    let recipient = Person.IMessage.Recipient(kind: .phoneNumber, value: "+1 646.863.9557")

    XCTAssertEqual(recipient.displayValue, "(646) 863-9557")
  }

  func testIMessageCustomPhoneNumberIsFormatted() {
    let recipient = Person.IMessage.Recipient(kind: .custom, value: "6468639557")

    XCTAssertEqual(recipient.displayValue, "(646) 863-9557")
  }

  func testIMessageCustomEmailIsUnchanged() {
    let recipient = Person.IMessage.Recipient(kind: .custom, value: "sam6468639557@example.com")

    XCTAssertEqual(recipient.displayValue, "sam6468639557@example.com")
  }
}
