#if !SWIFT_PACKAGE
  import XCTest
  @testable import open_receipt

  @MainActor
  final class SavedPeopleModelTests: XCTestCase {
    func testIncludingContactAdoptsItsPaymentDefaults() async throws {
      let model = makeModel()

      let included = await model.include(avery)

      let person = try XCTUnwrap(included)
      XCTAssertEqual(person.paymentMethods.venmo?.recipient, venmoPhone)
      XCTAssertEqual(person.paymentMethods.iMessage?.recipient, iMessagePhone)
    }

    func testAdoptContactPaymentDefaultsFillsMissingMethods() async throws {
      let model = makeModel()
      try await saveLinkedPerson(in: model)

      await model.adoptContactPaymentDefaults(from: client)

      let saved = try XCTUnwrap(model.people.first)
      XCTAssertEqual(saved.paymentMethods.venmo?.recipient, venmoPhone)
      XCTAssertEqual(saved.paymentMethods.iMessage?.recipient, iMessagePhone)
    }

    func testAdoptContactPaymentDefaultsKeepsExistingVenmo() async throws {
      let model = makeModel()
      try await saveLinkedPerson(in: model, venmo: .init(username: "avery"))

      await model.adoptContactPaymentDefaults(from: client)

      let saved = try XCTUnwrap(model.people.first)
      XCTAssertEqual(saved.paymentMethods.venmo?.recipient.kind, .username)
      XCTAssertEqual(saved.paymentMethods.venmo?.recipient.value, "avery")
      XCTAssertEqual(saved.paymentMethods.iMessage?.recipient, iMessagePhone)
    }

    func testDeleteRemovesPersonFromList() async throws {
      let model = makeModel()
      let included = await model.include(name: "Sam")
      let person = try XCTUnwrap(included)

      let didDelete = await model.delete(person)

      XCTAssertTrue(didDelete)
      XCTAssertTrue(model.people.isEmpty)
    }

    private let phone = "646-555-0100"

    private var venmoPhone: Person.Venmo.Recipient {
      Person.Venmo.Recipient(kind: .phoneNumber, value: phone)
    }

    private var iMessagePhone: Person.IMessage.Recipient {
      Person.IMessage.Recipient(kind: .phoneNumber, value: phone)
    }

    private var avery: ContactSummary {
      ContactSummary(
        identifier: "contact-1",
        displayName: "Avery",
        phoneNumbers: [.init(label: "mobile", value: phone)])
    }

    private var client: ContactClient {
      let contact = avery
      return ContactClient(
        authorizationStatus: { .authorized },
        requestAccess: { .authorized },
        fetchContacts: { _ in [contact] },
        fetchAvatar: { _ in nil })
    }

    private func makeModel() -> SavedPeopleModel {
      let rootURL = FileManager.default.temporaryDirectory
        .appending(
          path: "open-receipt-saved-people-tests-\(UUID().uuidString)",
          directoryHint: .isDirectory)
      addTeardownBlock { try? FileManager.default.removeItem(at: rootURL) }
      return SavedPeopleModel(storage: .files(PeopleFileStorage(rootURL: rootURL)))
    }

    private func saveLinkedPerson(
      in model: SavedPeopleModel,
      venmo: Person.Venmo? = nil
    ) async throws {
      let included = await model.include(name: avery.displayName)
      var person = try XCTUnwrap(included)
      person.contactIdentifier = avery.identifier
      person.paymentMethods.venmo = venmo
      let saved = await model.save(person)
      XCTAssertNotNil(saved)
    }
  }
#endif
