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

  func testAdoptingRecipientsFillsMissingVenmo() {
    var methods = Person.PaymentMethods()

    XCTAssertTrue(methods.adoptRecipients(of: avery))
    XCTAssertEqual(methods.venmo?.recipient, .init(kind: .phoneNumber, value: "646-555-0100"))
  }

  func testAdoptingRecipientsKeepsExistingVenmo() {
    var methods = Person.PaymentMethods()
    methods.venmo = .init(username: "avery")

    _ = methods.adoptRecipients(of: avery)

    XCTAssertEqual(methods.venmo?.recipient.value, "avery")
  }

  func testAdoptingRecipientsWithNothingMissingChangesNothing() {
    var methods = Person.PaymentMethods()
    methods.venmo = .init(username: "avery")
    methods.iMessage = .init(recipient: .init(kind: .custom, value: "avery"))

    XCTAssertFalse(methods.adoptRecipients(of: avery))
  }

  func testContactsWithoutAccessAreNone() async {
    let client = ContactClient.stub(status: .denied, contacts: [avery])

    let contacts = await client.contacts(withIdentifiers: ["contact-1"])

    XCTAssertTrue(contacts.isEmpty)
  }

  func testContactsAreByIdentifier() async {
    let client = ContactClient.stub(contacts: [avery])

    let contacts = await client.contacts(withIdentifiers: ["contact-1"])

    XCTAssertEqual(contacts["contact-1"], avery)
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

  private let avery = ContactSummary(
    identifier: "contact-1",
    displayName: "Avery",
    phoneNumbers: [.init(label: "mobile", value: "646-555-0100")])
}
