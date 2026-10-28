import XCTest

@testable import open_receipt

final class PersonTests: XCTestCase {
  func testPersonIsTheirOwnContact() {
    XCTAssertTrue(Person.fixture(name: "Sam", contactIdentifier: "sam").isContact("sam"))
  }

  func testPersonIsNotAnotherContact() {
    XCTAssertFalse(Person.fixture(name: "Sam", contactIdentifier: "sam").isContact("alex"))
  }

  func testPersonWithoutContactIsNeverAContact() {
    XCTAssertFalse(Person.fixture(name: "Sam").isContact(nil))
  }

  func testResolvesCurrentParticipantByPersonIdentifier() throws {
    let person = Person.fixture(name: "Sam")
    let participant = ReceiptParticipant(
      id: UUID(),
      personID: person.id,
      source: .manual,
      displayName: "Old name")

    XCTAssertEqual([person].person(for: participant), person)
  }

  func testDoesNotRelinkDeletedCurrentParticipantByName() {
    let participant = ReceiptParticipant(
      id: UUID(),
      personID: UUID(),
      source: .manual,
      displayName: "Sam")

    XCTAssertNil(
      [Person.fixture(name: "Sam")].person(for: participant))
  }

  func testResolvesLegacyAppleContactByContactIdentifier() throws {
    let person = Person.fixture(name: "New name", contactIdentifier: "contact-1")
    let participant = ReceiptParticipant(
      id: UUID(),
      source: .contact(identifier: "contact-1"),
      displayName: "Old name")

    XCTAssertEqual([person].person(for: participant), person)
  }

  func testResolvesLegacyCustomPersonByUniqueName() throws {
    let person = Person.fixture(name: "Sam")
    let participant = ReceiptParticipant(
      id: UUID(),
      source: .manual,
      displayName: "sam")

    XCTAssertEqual([person].person(for: participant), person)
  }

  func testDoesNotResolveAmbiguousLegacyCustomName() {
    let participant = ReceiptParticipant(
      id: UUID(),
      source: .manual,
      displayName: "Sam")

    XCTAssertNil(
      [Person.fixture(name: "Sam"), Person.fixture(name: "Sam")].person(for: participant))
  }

  func testRelinksDeletedContactParticipantToReaddedContact() {
    let person = Person.fixture(name: "Sam", contactIdentifier: "contact-1")
    let participant = ReceiptParticipant(
      id: UUID(),
      personID: UUID(),
      source: .contact(identifier: "contact-1"),
      displayName: "Sam")

    XCTAssertEqual([person].person(for: participant), person)
  }

  func testPrefersLinkedPersonOverSameContact() {
    let linked = Person.fixture(name: "Sam", contactIdentifier: "contact-1")
    let other = Person.fixture(name: "Sam", contactIdentifier: "contact-1")
    let participant = ReceiptParticipant(
      id: UUID(),
      personID: linked.id,
      source: .contact(identifier: "contact-1"),
      displayName: "Sam")

    XCTAssertEqual([other, linked].person(for: participant), linked)
  }

  func testDoesNotResolveOwnerByContactIdentifier() {
    let participant = ReceiptParticipant(
      id: UUID(),
      source: .currentUser(contactIdentifier: "me"),
      displayName: "Alex")

    XCTAssertNil(
      [Person.fixture(name: "Sam", contactIdentifier: "me")].person(for: participant))
  }
}
