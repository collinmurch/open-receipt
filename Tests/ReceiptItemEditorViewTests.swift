import XCTest

@testable import open_receipt

final class ReceiptItemEditorViewTests: XCTestCase {
  func testReturnAtEndOfNameIsRemoved() {
    XCTAssertEqual(ReceiptItemEditorView.singleLine("Oat Milk\n"), "Oat Milk")
  }

  func testLineBreaksInPastedNameBecomeSpaces() {
    XCTAssertEqual(ReceiptItemEditorView.singleLine("Oat\nMilk\r\n2%"), "Oat Milk 2%")
  }
}
