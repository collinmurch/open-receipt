import XCTest

@testable import open_receipt

@MainActor
final class ContactClientTests: XCTestCase {
  func testContactDefaultsVenmoToFirstPhoneNumber() {
    let contact = ContactSummary(
      identifier: "1",
      displayName: "Avery",
      phoneNumbers: [
        .init(label: "mobile", value: "646-555-0100"),
        .init(label: "home", value: "212-555-0100"),
      ],
      emailAddresses: [.init(label: "home", value: "avery@example.com")])

    XCTAssertEqual(contact.defaultRecipient(Person.Venmo.Recipient.self)?.kind, .phoneNumber)
    XCTAssertEqual(contact.defaultRecipient(Person.Venmo.Recipient.self)?.value, "646-555-0100")
  }

  func testContactDefaultsVenmoToEmailWhenPhoneIsUnavailable() {
    let contact = ContactSummary(
      identifier: "1",
      displayName: "Avery",
      emailAddresses: [.init(label: "home", value: "avery@example.com")])

    XCTAssertEqual(contact.defaultRecipient(Person.Venmo.Recipient.self)?.kind, .emailAddress)
    XCTAssertEqual(
      contact.defaultRecipient(Person.Venmo.Recipient.self)?.value, "avery@example.com")
  }

  func testContactHasNoDefaultVenmoRecipientWithoutContactValues() {
    let contact = ContactSummary(identifier: "1", displayName: "Avery")

    XCTAssertNil(contact.defaultRecipient(Person.Venmo.Recipient.self))
  }

  func testContactMergesMobileAndIPhoneLabelsForSameNumber() throws {
    let contact = ContactSummary(
      identifier: "1",
      displayName: "Avery",
      phoneNumbers: [
        .init(label: "iPhone", value: "+1 (646) 555-0100"),
        .init(label: "mobile", value: "646-555-0100"),
      ])

    let phoneNumber = try XCTUnwrap(contact.phoneNumbers.first)
    XCTAssertEqual(contact.phoneNumbers.count, 1)
    XCTAssertEqual(phoneNumber.label?.lowercased(), "mobile")
  }

  func testContactPrefersMobileLabelForDuplicateNumber() throws {
    let contact = ContactSummary(
      identifier: "1",
      displayName: "Avery",
      phoneNumbers: [
        .init(label: "home", value: "646-555-0100"),
        .init(label: "mobile", value: "(646) 555-0100"),
      ])

    let phoneNumber = try XCTUnwrap(contact.phoneNumbers.first)
    XCTAssertEqual(contact.phoneNumbers.count, 1)
    XCTAssertEqual(phoneNumber.label, "mobile")
  }

  func testContactKeepsDistinctMobileNumbers() {
    let contact = ContactSummary(
      identifier: "1",
      displayName: "Avery",
      phoneNumbers: [
        .init(label: "mobile", value: "646-555-0100"),
        .init(label: "iPhone", value: "212-555-0100"),
      ])

    XCTAssertEqual(contact.phoneNumbers.count, 2)
    XCTAssertTrue(contact.phoneNumbers.allSatisfy { $0.label?.lowercased() == "mobile" })
  }

  func testDefaultPaymentMethodsDoNotReplaceExistingVenmoChoice() async {
    let contact = ContactSummary(
      identifier: "contact-1",
      displayName: "Avery",
      phoneNumbers: [.init(label: "mobile", value: "646-555-0100")])
    let client = ContactClient(
      authorizationStatus: { .authorized },
      requestAccess: { .authorized },
      fetchContacts: { _ in [contact] },
      fetchAvatar: { _ in nil })
    let unconfigured = Person.fixture(name: "Avery", contactIdentifier: "contact-1")
    var configured = Person.fixture(name: "Avery", contactIdentifier: "contact-1")
    configured.paymentMethods.venmo = .init(username: "avery")

    let defaults = await client.defaultPaymentMethods(for: [unconfigured, configured])

    XCTAssertEqual(defaults[unconfigured.id]?.venmo?.kind, .phoneNumber)
    XCTAssertEqual(defaults[unconfigured.id]?.venmo?.value, "646-555-0100")
    XCTAssertNil(defaults[configured.id]?.venmo)
  }

  func testContactDefaultsIMessageToFirstPhoneNumber() {
    let contact = ContactSummary(
      identifier: "1",
      displayName: "Avery",
      phoneNumbers: [.init(label: "mobile", value: "646-555-0100")],
      emailAddresses: [.init(label: "home", value: "avery@example.com")])

    XCTAssertEqual(contact.defaultRecipient(Person.IMessage.Recipient.self)?.kind, .phoneNumber)
    XCTAssertEqual(contact.defaultRecipient(Person.IMessage.Recipient.self)?.value, "646-555-0100")
  }

  func testContactDefaultsIMessageToEmailWhenPhoneIsUnavailable() {
    let contact = ContactSummary(
      identifier: "1",
      displayName: "Avery",
      emailAddresses: [.init(label: "home", value: "avery@example.com")])

    XCTAssertEqual(contact.defaultRecipient(Person.IMessage.Recipient.self)?.kind, .emailAddress)
    XCTAssertEqual(
      contact.defaultRecipient(Person.IMessage.Recipient.self)?.value, "avery@example.com")
  }
}
