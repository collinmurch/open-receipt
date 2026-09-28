#if !SWIFT_PACKAGE
  import XCTest
  @testable import open_receipt

  final class PeopleStorageTests: XCTestCase {
    private var rootURL: URL!
    private var storage: PeopleFileStorage!

    override func setUp() {
      super.setUp()
      rootURL = FileManager.default.temporaryDirectory
        .appending(
          path: "open-receipt-people-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
      storage = PeopleFileStorage(rootURL: rootURL)
    }

    override func tearDown() {
      if let rootURL {
        try? FileManager.default.removeItem(at: rootURL)
      }
      storage = nil
      rootURL = nil
      super.tearDown()
    }

    func testIncludedPeopleAreSortedByMostRecentUse() async throws {
      _ = try await storage.include(
        id: nil,
        displayName: "Older",
        contactIdentifier: nil,
        at: Date(timeIntervalSince1970: 1))
      _ = try await storage.include(
        id: nil,
        displayName: "Newer",
        contactIdentifier: nil,
        at: Date(timeIntervalSince1970: 2))

      let people = try await storage.list()

      XCTAssertEqual(people.map(\.displayName), ["Newer", "Older"])
    }

    func testIncludingSavedPersonUpdatesLastIncludedDate() async throws {
      let person = try await storage.include(
        id: nil,
        displayName: "Sam",
        contactIdentifier: nil,
        at: Date(timeIntervalSince1970: 1))

      let updated = try await storage.include(
        id: person.id,
        displayName: person.displayName,
        contactIdentifier: nil,
        at: Date(timeIntervalSince1970: 2))

      XCTAssertEqual(updated.id, person.id)
      XCTAssertEqual(updated.lastIncludedAt, Date(timeIntervalSince1970: 2))
    }

    func testContactIdentifierDeduplicatesPeople() async throws {
      let first = try await storage.include(
        id: nil,
        displayName: "Sam",
        contactIdentifier: "contact-1",
        at: Date(timeIntervalSince1970: 1))

      let second = try await storage.include(
        id: nil,
        displayName: "Sam Lee",
        contactIdentifier: "contact-1",
        at: Date(timeIntervalSince1970: 2))
      let people = try await storage.list()

      XCTAssertEqual(second.id, first.id)
      XCTAssertEqual(people.count, 1)
      XCTAssertEqual(second.displayName, "Sam Lee")
    }

    func testManualPeopleWithEqualNamesRemainDistinct() async throws {
      _ = try await storage.include(
        id: nil,
        displayName: "Sam",
        contactIdentifier: nil,
        at: Date(timeIntervalSince1970: 1))
      _ = try await storage.include(
        id: nil,
        displayName: "Sam",
        contactIdentifier: nil,
        at: Date(timeIntervalSince1970: 2))
      let people = try await storage.list()

      XCTAssertEqual(people.count, 2)
    }

    func testSaveNormalizesVenmoUsername() async throws {
      var person = try await storage.include(
        id: nil,
        displayName: "Sam",
        contactIdentifier: nil,
        at: Date(timeIntervalSince1970: 1))
      person.paymentMethods.venmo = .init(username: " @sam ")

      let saved = try await storage.save(person)

      XCTAssertEqual(saved.paymentMethods.venmo?.recipient.value, "sam")
      XCTAssertEqual(saved.paymentMethods.venmo?.customUsername, "sam")
    }

    func testSaveNormalizesVenmoRecipientAndPreservesCustomUsername() async throws {
      var person = try await storage.include(
        id: nil,
        displayName: "Sam",
        contactIdentifier: "contact-1",
        at: Date(timeIntervalSince1970: 1))
      person.paymentMethods.venmo = .init(
        recipient: .init(kind: .phoneNumber, value: "  646.863.9557  "),
        customUsername: " @sam ")

      let saved = try await storage.save(person)

      XCTAssertEqual(saved.paymentMethods.venmo?.recipient.value, "646.863.9557")
      XCTAssertEqual(saved.paymentMethods.venmo?.customUsername, "sam")
    }

    func testSaveNormalizesCashAppCashtag() async throws {
      var person = try await storage.include(
        id: nil,
        displayName: "Sam",
        contactIdentifier: nil,
        at: Date(timeIntervalSince1970: 1))
      person.paymentMethods.cashApp = .init(cashtag: " $$sam-123 ")

      let saved = try await storage.save(person)

      XCTAssertEqual(saved.paymentMethods.cashApp?.cashtag, "sam-123")
      XCTAssertEqual(saved.paymentMethods.cashApp?.displayValue, "$sam-123")
    }

    func testSaveNormalizesIMessageRecipient() async throws {
      var person = try await storage.include(
        id: nil,
        displayName: "Sam",
        contactIdentifier: nil,
        at: Date(timeIntervalSince1970: 1))
      person.paymentMethods.iMessage = .init(
        recipient: .init(kind: .custom, value: " sam@example.com "))

      let saved = try await storage.save(person)

      XCTAssertEqual(saved.paymentMethods.iMessage?.recipient.value, "sam@example.com")
    }

    func testSavePersistsContactDefaultPaymentMethod() async throws {
      var person = try await storage.include(
        id: nil,
        displayName: "Sam",
        contactIdentifier: nil,
        at: Date(timeIntervalSince1970: 1))
      person.paymentMethods.defaultMethod = PaymentMethod.none

      _ = try await storage.save(person)
      let people = try await storage.list()
      let saved = try XCTUnwrap(people.first)

      XCTAssertEqual(saved.paymentMethods.defaultMethod, PaymentMethod.none)
    }

    func testLegacyVenmoUsernameDecodesAsRecipient() throws {
      let data = try XCTUnwrap(#"{"username":"sam"}"#.data(using: .utf8))

      let venmo = try JSONDecoder().decode(Person.Venmo.self, from: data)

      XCTAssertEqual(venmo.recipient.kind, .username)
      XCTAssertEqual(venmo.recipient.value, "sam")
      XCTAssertEqual(venmo.customUsername, "sam")
    }

    func testDeleteRemovesSavedPerson() async throws {
      let person = try await storage.include(
        id: nil,
        displayName: "Sam",
        contactIdentifier: nil,
        at: Date(timeIntervalSince1970: 1))

      try await storage.delete(id: person.id)
      let people = try await storage.list()

      XCTAssertTrue(people.isEmpty)
    }

    func testLegacyImportMergesContactsAndKeepsManualPeopleDistinct() async throws {
      let snapshots = [
        snapshot(name: "Sam", contactIdentifier: "contact-1", time: 1),
        snapshot(name: "Sam Lee", contactIdentifier: "contact-1", time: 2),
        snapshot(name: "Alex", contactIdentifier: nil, time: 3),
        snapshot(name: "Alex", contactIdentifier: nil, time: 4),
      ]

      try await storage.importReceiptParticipants(snapshots)
      let people = try await storage.list()

      XCTAssertEqual(people.count, 3)
      XCTAssertEqual(people.filter { $0.contactIdentifier == "contact-1" }.count, 1)
      XCTAssertEqual(people.filter { $0.displayName == "Alex" }.count, 2)
    }

    func testLegacyImportRunsOnlyOnce() async throws {
      let snapshot = snapshot(name: "Sam", contactIdentifier: nil, time: 1)
      try await storage.importReceiptParticipants([snapshot])
      let importedPeople = try await storage.list()
      let person = try XCTUnwrap(importedPeople.first)
      try await storage.delete(id: person.id)

      try await storage.importReceiptParticipants([snapshot])
      let people = try await storage.list()

      XCTAssertTrue(people.isEmpty)
    }

    func testOwnerIsUnsetByDefault() async throws {
      let owner = try await storage.owner()

      XCTAssertNil(owner)
    }

    func testSetOwnerPersists() async throws {
      let owner = ReceiptOwner(contactIdentifier: "me", displayName: "Alex")

      try await storage.setOwner(owner)

      let reloaded = PeopleFileStorage(rootURL: rootURL)
      let stored = try await reloaded.owner()
      XCTAssertEqual(stored, owner)
    }

    func testSetOwnerReplacesExistingOwner() async throws {
      try await storage.setOwner(ReceiptOwner(contactIdentifier: "a", displayName: "Alex"))
      let replacement = ReceiptOwner(contactIdentifier: "b", displayName: "Blair")

      try await storage.setOwner(replacement)

      let stored = try await storage.owner()
      XCTAssertEqual(stored, replacement)
    }

    func testSetOwnerToNilClearsOwner() async throws {
      try await storage.setOwner(ReceiptOwner(contactIdentifier: "a", displayName: "Alex"))

      try await storage.setOwner(nil)

      let stored = try await storage.owner()
      XCTAssertNil(stored)
    }

    func testAdoptOwnerStoresOwnerWhenUnset() async throws {
      let owner = ReceiptOwner(contactIdentifier: "a", displayName: "Alex")

      let adopted = try await storage.adoptOwner(owner)

      let stored = try await storage.owner()
      XCTAssertEqual(adopted, owner)
      XCTAssertEqual(stored, owner)
    }

    func testAdoptOwnerKeepsExistingOwner() async throws {
      let existing = ReceiptOwner(contactIdentifier: "a", displayName: "Alex")
      try await storage.setOwner(existing)

      let adopted = try await storage.adoptOwner(
        ReceiptOwner(contactIdentifier: "b", displayName: "Blair"))

      let stored = try await storage.owner()
      XCTAssertEqual(adopted, existing)
      XCTAssertEqual(stored, existing)
    }

    func testOwnerDoesNotAffectPeopleList() async throws {
      try await storage.setOwner(ReceiptOwner(contactIdentifier: "a", displayName: "Alex"))

      let people = try await storage.list()

      XCTAssertTrue(people.isEmpty)
    }

    private func snapshot(
      name: String,
      contactIdentifier: String?,
      time: TimeInterval
    ) -> ReceiptPersonSnapshot {
      ReceiptPersonSnapshot(
        receiptID: UUID(),
        participantID: UUID(),
        personID: nil,
        displayName: name,
        contactIdentifier: contactIdentifier,
        includedAt: Date(timeIntervalSince1970: time))
    }
  }
#endif
