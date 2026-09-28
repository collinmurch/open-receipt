#if !SWIFT_PACKAGE
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

    func testLegacyBlueStyleDecodes() throws {
      let style = try decodeLegacyStyle("blue")

      XCTAssertEqual(style, .blue)
    }

    func testLegacyMintStyleDecodes() throws {
      let style = try decodeLegacyStyle("mint")

      XCTAssertEqual(style, .mint)
    }

    func testLegacyPeachStyleDecodes() throws {
      let style = try decodeLegacyStyle("peach")

      XCTAssertEqual(style, .peach)
    }

    func testLegacyVioletStyleDecodes() throws {
      let style = try decodeLegacyStyle("violet")

      XCTAssertEqual(style, .violet)
    }

    private func decodeLegacyStyle(_ value: String) throws -> ReceiptBackgroundStyle {
      try JSONDecoder().decode(ReceiptBackgroundStyle.self, from: Data("\"\(value)\"".utf8))
    }
  }
#endif
