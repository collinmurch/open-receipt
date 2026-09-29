import XCTest

@testable import open_receipt

final class ReceiptPersonResolverTests: XCTestCase {
  func testResolvesCurrentParticipantByPersonIdentifier() throws {
    let person = makePerson(name: "Sam")
    let participant = ReceiptParticipant(
      id: UUID(),
      personID: person.id,
      source: .manual,
      displayName: "Old name",
      avatarData: nil)

    XCTAssertEqual(ReceiptPersonResolver.person(for: participant, in: [person]), person)
  }

  func testDoesNotRelinkDeletedCurrentParticipantByName() {
    let participant = ReceiptParticipant(
      id: UUID(),
      personID: UUID(),
      source: .manual,
      displayName: "Sam",
      avatarData: nil)

    XCTAssertNil(
      ReceiptPersonResolver.person(for: participant, in: [makePerson(name: "Sam")]))
  }

  func testResolvesLegacyAppleContactByContactIdentifier() throws {
    let person = makePerson(name: "New name", contactIdentifier: "contact-1")
    let participant = ReceiptParticipant(
      id: UUID(),
      source: .contact(identifier: "contact-1"),
      displayName: "Old name",
      avatarData: nil)

    XCTAssertEqual(ReceiptPersonResolver.person(for: participant, in: [person]), person)
  }

  func testResolvesLegacyCustomPersonByUniqueName() throws {
    let person = makePerson(name: "Sam")
    let participant = ReceiptParticipant(
      id: UUID(),
      source: .manual,
      displayName: "sam",
      avatarData: nil)

    XCTAssertEqual(ReceiptPersonResolver.person(for: participant, in: [person]), person)
  }

  func testDoesNotResolveAmbiguousLegacyCustomName() {
    let participant = ReceiptParticipant(
      id: UUID(),
      source: .manual,
      displayName: "Sam",
      avatarData: nil)

    XCTAssertNil(
      ReceiptPersonResolver.person(
        for: participant,
        in: [makePerson(name: "Sam"), makePerson(name: "Sam")]))
  }

  private func makePerson(
    name: String,
    contactIdentifier: String? = nil
  ) -> Person {
    let date = Date(timeIntervalSince1970: 1)
    return Person(
      id: UUID(),
      createdAt: date,
      updatedAt: date,
      lastIncludedAt: date,
      displayName: name,
      contactIdentifier: contactIdentifier,
      paymentMethods: .init())
  }
}
