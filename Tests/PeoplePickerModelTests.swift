import XCTest

@testable import open_receipt

@MainActor
final class PeoplePickerModelTests: XCTestCase {
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
    let client = makeClient(status: .authorized, contacts: [contact])
    let unconfigured = makePerson(id: UUID(), contactIdentifier: "contact-1")
    var configured = makePerson(id: UUID(), contactIdentifier: "contact-1")
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

  func testLoadRequestsAccessWhenStatusIsNotDetermined() async {
    let model = PeoplePickerModel(
      client: makeClient(
        status: .notDetermined,
        requestedStatus: .limited,
        contacts: [ContactSummary(identifier: "1", displayName: "Avery")]))

    await model.load()

    XCTAssertEqual(model.authorization, .limited)
    XCTAssertEqual(model.contacts.map(\.displayName), ["Avery"])
  }

  func testLoadFetchesAuthorizedContacts() async {
    let model = PeoplePickerModel(
      client: makeClient(
        status: .authorized,
        contacts: [ContactSummary(identifier: "1", displayName: "Morgan")]))

    await model.load()

    XCTAssertEqual(model.authorization, .authorized)
    XCTAssertEqual(model.contacts.map(\.displayName), ["Morgan"])
  }

  func testLoadDoesNotFetchWhenAccessIsDenied() async {
    let model = PeoplePickerModel(client: makeClient(status: .denied))

    await model.load()

    XCTAssertEqual(model.authorization, .denied)
    XCTAssertTrue(model.contacts.isEmpty)
    XCTAssertNil(model.errorDescription)
  }

  func testLoadDoesNotFetchWhenAccessIsRestricted() async {
    let model = PeoplePickerModel(client: makeClient(status: .restricted))

    await model.load()

    XCTAssertEqual(model.authorization, .restricted)
    XCTAssertTrue(model.contacts.isEmpty)
    XCTAssertNil(model.errorDescription)
  }

  func testSearchIsCaseInsensitive() async {
    let model = PeoplePickerModel(
      client: makeClient(
        status: .authorized,
        contacts: [
          ContactSummary(identifier: "1", displayName: "Alex Morgan"),
          ContactSummary(identifier: "2", displayName: "Sam Lee"),
        ]))
    await model.load()

    model.searchText = "mORg"

    XCTAssertEqual(model.filteredContacts.map(\.displayName), ["Alex Morgan"])
  }

  func testResolvedContactsMergeWithoutDuplicates() async {
    let contact = ContactSummary(identifier: "1", displayName: "Alex Morgan")
    let model = PeoplePickerModel(
      client: makeClient(status: .limited, contacts: [contact]))
    await model.load()

    _ = await model.resolveContacts(identifiers: ["1"])

    XCTAssertEqual(model.contacts, [contact])
  }

  func testRequestFailureIsPresented() async {
    let client = ContactClient(
      authorizationStatus: { .notDetermined },
      requestAccess: { throw ContactTestError.failed },
      fetchContacts: { _ in [] },
      fetchAvatar: { _ in nil })
    let model = PeoplePickerModel(client: client)

    await model.load()

    XCTAssertNotNil(model.errorDescription)
  }

  func testReloadReplacesCachedContacts() async {
    let responses = ContactResponseSequence([
      [ContactSummary(identifier: "1", displayName: "Alex")],
      [ContactSummary(identifier: "2", displayName: "Morgan")],
    ])
    let client = ContactClient(
      authorizationStatus: { .authorized },
      requestAccess: { .authorized },
      fetchContacts: { _ in await responses.next() },
      fetchAvatar: { _ in nil })
    let model = PeoplePickerModel(client: client)
    await model.load()

    await model.reload()

    XCTAssertEqual(model.contacts.map(\.displayName), ["Morgan"])
  }

  func testMissingAvatarIsFetchedOnce() async {
    let fetches = ContactAvatarFetchRecorder()
    let client = ContactClient(
      authorizationStatus: { .authorized },
      requestAccess: { .authorized },
      fetchContacts: { _ in [] },
      fetchAvatar: { identifier in await fetches.fetch(identifier) })
    let model = PeoplePickerModel(client: client)

    _ = await model.avatar(for: "1")
    _ = await model.avatar(for: "1")

    let count = await fetches.count
    XCTAssertEqual(count, 1)
  }

  private func makeClient(
    status: ContactAuthorization,
    requestedStatus: ContactAuthorization? = nil,
    contacts: [ContactSummary] = []
  ) -> ContactClient {
    ContactClient(
      authorizationStatus: { status },
      requestAccess: { requestedStatus ?? status },
      fetchContacts: { identifiers in
        guard let identifiers else { return contacts }
        return contacts.filter { identifiers.contains($0.identifier) }
      },
      fetchAvatar: { _ in nil })
  }

  private func makePerson(id: UUID, contactIdentifier: String) -> Person {
    Person(
      id: id,
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1),
      lastIncludedAt: Date(timeIntervalSince1970: 1),
      displayName: "Avery",
      contactIdentifier: contactIdentifier,
      paymentMethods: .init())
  }
}

private enum ContactTestError: Error {
  case failed
}

private actor ContactResponseSequence {
  private var responses: [[ContactSummary]]

  init(_ responses: [[ContactSummary]]) {
    self.responses = responses
  }

  func next() -> [ContactSummary] {
    responses.removeFirst()
  }
}

private actor ContactAvatarFetchRecorder {
  private(set) var count = 0

  func fetch(_ identifier: String) -> Data? {
    count += 1
    return nil
  }
}
