import XCTest

@testable import open_receipt

final class ReceiptParsingClientTests: XCTestCase {
  func testSampleClientIsMarkedAsSampleData() {
    XCTAssertTrue(ReceiptParsingClient.sample.usesSampleData)
  }

  func testSampleClientParsesWithoutReceiptPages() async throws {
    let receipt = try await ReceiptParsingClient.sample(pacing: .zero).stream([]) { _ in }

    XCTAssertEqual(receipt.merchantName, "Juniper Market")
    XCTAssertEqual(receipt.items.count, 3)
    XCTAssertEqual(receipt.total, 36.94)
  }

  func testSampleClientStreamsItemsOneAtATime() async throws {
    let previews = PreviewRecorder()

    _ = try await ReceiptParsingClient.sample(pacing: .zero).stream([]) { preview in
      await previews.append(preview)
    }

    let itemCounts = await previews.values.map(\.items.count)
    XCTAssertEqual(itemCounts.first, 0)
    XCTAssertTrue(itemCounts.contains(1))
    XCTAssertEqual(itemCounts.last, 3)
  }

  func testSampleClientStreamsItemNamesBeforeTotals() async throws {
    let previews = PreviewRecorder()

    _ = try await ReceiptParsingClient.sample(pacing: .zero).stream([]) { preview in
      await previews.append(preview)
    }

    let values = await previews.values
    XCTAssertTrue(
      values.contains { preview in
        preview.items.first?.description == "Breakfast"
          && preview.items.first?.lineTotal == nil
      })
  }

  func testClientWithoutProgressIgnoresPreviews() async throws {
    let client = ReceiptParsingClient(usesSampleData: false) { _ in
      ParsedReceipt(merchantName: "Cafe")
    }

    let receipt = try await client.stream([]) { _ in }

    XCTAssertEqual(receipt.merchantName, "Cafe")
  }

  func testLiveClientIsNotMarkedAsSampleData() {
    XCTAssertFalse(ReceiptParsingClient.live.usesSampleData)
  }

  func testSampleReceiptsStartOnInDevelopment() {
    XCTAssertTrue(SampleReceipts.isEnabled(in: .development, defaults: isolatedDefaults()))
  }

  func testSampleReceiptsStartOffInTestFlight() {
    XCTAssertFalse(SampleReceipts.isEnabled(in: .testFlight, defaults: isolatedDefaults()))
  }

  func testSampleReceiptsFollowSettingInTestFlight() {
    let defaults = isolatedDefaults()
    defaults.set(true, forKey: SampleReceipts.key)

    XCTAssertTrue(SampleReceipts.isEnabled(in: .testFlight, defaults: defaults))
  }

  func testSampleReceiptsNeverApplyInAppStore() {
    let defaults = isolatedDefaults()
    defaults.set(true, forKey: SampleReceipts.key)

    XCTAssertFalse(SampleReceipts.isEnabled(in: .appStore, defaults: defaults))
  }

  private func isolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "ReceiptParsingClientTests-\(UUID().uuidString)")!
  }
}

private actor PreviewRecorder {
  private(set) var values: [ReceiptParsePreview] = []

  func append(_ preview: ReceiptParsePreview) {
    values.append(preview)
  }
}
