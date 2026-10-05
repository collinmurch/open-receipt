import XCTest

@testable import open_receipt

final class SampleReceiptsTests: XCTestCase {
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
}
