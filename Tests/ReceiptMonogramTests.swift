import XCTest

@testable import open_receipt

final class ReceiptMonogramTests: XCTestCase {
  func testInitialsUseFirstTwoWords() {
    XCTAssertEqual(ReceiptMonogram.initials(for: "Juniper Market"), "JM")
  }

  func testInitialsUseSingleWord() {
    XCTAssertEqual(ReceiptMonogram.initials(for: "starbucks"), "S")
  }

  func testInitialsSkipPunctuation() {
    XCTAssertEqual(ReceiptMonogram.initials(for: "Trader Joe's #552"), "TJ")
  }

  func testInitialsSplitOnHyphen() {
    XCTAssertEqual(ReceiptMonogram.initials(for: "Chick-fil-A"), "CF")
  }

  func testInitialsReturnNilForBlankName() {
    XCTAssertNil(ReceiptMonogram.initials(for: "  "))
  }
}
