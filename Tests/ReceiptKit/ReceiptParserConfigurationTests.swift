import XCTest

#if SWIFT_PACKAGE
  @testable import ReceiptKit
#else
  @testable import open_receipt
#endif

final class ReceiptParserConfigurationTests: XCTestCase {
  func testStandardConfigurationHasNoVariant() {
    XCTAssertNil(ReceiptParserConfiguration.standard.variantDescription)
  }

  func testConfigurationDescribesChangedReasoning() {
    let configuration = ReceiptParserConfiguration(reasoningLevel: .light)

    XCTAssertEqual(configuration.variantDescription, "reasoning=light")
  }

  func testConfigurationDescribesPixelLimit() {
    let configuration = ReceiptParserConfiguration(maxPixelDimension: 2048)

    XCTAssertEqual(configuration.variantDescription, "max-pixels=2048")
  }
}
