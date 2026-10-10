import XCTest

@testable import open_receipt

@MainActor
final class PeoplePickerModelTests: XCTestCase {

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
      requestAccess: { throw TestError.failed },
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
