import Foundation
import XCTest

#if SWIFT_PACKAGE
  @testable import ReceiptKit
#else
  @testable import open_receipt
#endif

#if os(macOS)
  import FoundationModels
#endif

final class ReceiptParserSupportTests: XCTestCase {

  func testPreviewItemTotalSumsKnownLineTotals() {
    let preview = ReceiptParsePreview(items: [
      .init(description: "Coffee", lineTotal: 4.5),
      .init(description: "Muffin"),
      .init(description: "Tea", lineTotal: 3),
    ])

    XCTAssertEqual(preview.itemTotal, 7.5, accuracy: 0.0001)
  }

  func testConnectionFailureIsRetryable() {
    XCTAssertTrue(ReceiptParserError.connectionUnavailable.isRetryable)
    XCTAssertTrue(ReceiptParserError.connectionUnavailable.isConnectionFailure)
  }

  func testRefusalIsNotRetryable() {
    XCTAssertFalse(ReceiptParserError.refused.isRetryable)
  }

  func testQuotaFailureIsNotAConnectionFailure() {
    XCTAssertFalse(ReceiptParserError.quotaLimitReached(resetDate: nil).isConnectionFailure)
  }

  #if os(macOS)
    func testPreviewReadsPartialResponse() throws {
      let partial = try ReceiptModelContract.Response.PartiallyGenerated(
        GeneratedContent(
          json: """
            {"merchantName": " Juniper Market ", "total": 36.94, "currency": "usd",
             "items": [{"description": "Cold Brew", "quantity": 1, "lineTotal": 6.5},
                       {"description": "Muf"}]}
            """))

      let preview = ReceiptModelContract.preview(from: partial)

      XCTAssertEqual(preview.merchantName, "Juniper Market")
      XCTAssertEqual(preview.total, 36.94)
      XCTAssertEqual(preview.currency, "USD")
      XCTAssertEqual(preview.items.map(\.description), ["Cold Brew", "Muf"])
      XCTAssertNil(preview.items.last?.lineTotal)
    }

    func testPreviewHidesIncompleteCurrency() throws {
      let partial = try ReceiptModelContract.Response.PartiallyGenerated(
        GeneratedContent(json: #"{"currency": "US"}"#))

      XCTAssertNil(ReceiptModelContract.preview(from: partial).currency)
    }

    func testPreviewSkipsItemsWithoutDescription() throws {
      let partial = try ReceiptModelContract.Response.PartiallyGenerated(
        GeneratedContent(json: #"{"items": [{"lineTotal": 2}]}"#))

      XCTAssertTrue(ReceiptModelContract.preview(from: partial).items.isEmpty)
    }

    func testNetworkFailureMapsToConnectionFailure() {
      let error = PrivateCloudComputeLanguageModel.Error.networkFailure(
        .init(debugDescription: "offline"))

      XCTAssertEqual(ReceiptParser.parserError(for: error), .connectionUnavailable)
    }

    func testQuotaFailureKeepsResetDate() {
      let resetDate = Date(timeIntervalSince1970: 2_000_000_000)
      let error = PrivateCloudComputeLanguageModel.Error.quotaLimitReached(
        .init(resetDate: resetDate, debugDescription: "limit"))

      XCTAssertEqual(
        ReceiptParser.parserError(for: error), .quotaLimitReached(resetDate: resetDate))
    }

    func testRateLimitMapsToRateLimited() {
      let error = LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "slow"))

      XCTAssertEqual(ReceiptParser.parserError(for: error), .rateLimited(resetDate: nil))
    }

    func testContextOverflowMapsToTooManyPages() {
      let error = LanguageModelError.contextSizeExceeded(
        .init(contextSize: 10, tokenCount: 20, debugDescription: "large"))

      XCTAssertEqual(ReceiptParser.parserError(for: error), .tooManyPages)
    }

    func testURLErrorMapsToConnectionFailure() {
      XCTAssertEqual(
        ReceiptParser.parserError(for: URLError(.notConnectedToInternet)), .connectionUnavailable)
    }
  #endif
}
