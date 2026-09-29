import XCTest

@testable import open_receipt

final class ReceiptBackgroundStyleTests: XCTestCase {
  func testRandomStyleUsesTwoDistinctColors() {
    for _ in 0..<100 {
      let style = ReceiptBackgroundStyle.random()

      XCTAssertNotEqual(style.primary, style.secondary)
    }
  }

  func testColorPairRoundTrips() throws {
    let style = ReceiptBackgroundStyle(primary: .amber, secondary: .indigo)

    let data = try JSONEncoder().encode(style)
    let decoded = try JSONDecoder().decode(ReceiptBackgroundStyle.self, from: data)

    XCTAssertEqual(decoded, style)
  }
}
