#if !SWIFT_PACKAGE
  import XCTest
  @testable import open_receipt

  final class ReceiptLibraryDateFormatterTests: XCTestCase {
    func testFormatsReceiptDateWithOrdinalDay() {
      XCTAssertEqual(
        ReceiptLibraryDateFormatter.formatted(localDate: "2026-08-10"),
        "August 10th, 2026")
    }

    func testFormatsFirstWithStSuffix() {
      XCTAssertEqual(
        ReceiptLibraryDateFormatter.formatted(localDate: "2026-08-01"),
        "August 1st, 2026")
    }

    func testFormatsSecondWithNdSuffix() {
      XCTAssertEqual(
        ReceiptLibraryDateFormatter.formatted(localDate: "2026-08-02"),
        "August 2nd, 2026")
    }

    func testFormatsThirdWithRdSuffix() {
      XCTAssertEqual(
        ReceiptLibraryDateFormatter.formatted(localDate: "2026-08-03"),
        "August 3rd, 2026")
    }

    func testFormatsEleventhWithThSuffix() {
      XCTAssertEqual(
        ReceiptLibraryDateFormatter.formatted(localDate: "2026-08-11"),
        "August 11th, 2026")
    }

    func testRejectsInvalidDate() {
      XCTAssertNil(ReceiptLibraryDateFormatter.formatted(localDate: "2026-02-31"))
    }

    func testDayTitleLeavesOutYear() {
      XCTAssertEqual(ReceiptLibraryDateFormatter.dayTitle(localDate: "2026-08-10"), "August 10th")
    }

    func testNormalizedDayPadsMonthAndDay() {
      XCTAssertEqual(ReceiptLibraryDateFormatter.normalizedDay(localDate: "2026-8-1"), "2026-08-01")
    }

    func testNormalizedDayRejectsInvalidDate() {
      XCTAssertNil(ReceiptLibraryDateFormatter.normalizedDay(localDate: "2026-02-31"))
    }

    func testMonthTitleOmitsCurrentYear() {
      XCTAssertEqual(
        ReceiptLibraryDateFormatter.monthTitle(month: "2026-08", currentYear: 2026), "August")
    }

    func testMonthTitleIncludesPastYear() {
      XCTAssertEqual(
        ReceiptLibraryDateFormatter.monthTitle(month: "2025-12", currentYear: 2026),
        "December 2025")
    }
  }
#endif
