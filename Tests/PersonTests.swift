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
}
