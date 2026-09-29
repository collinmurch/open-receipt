import XCTest

@testable import open_receipt

final class ReceiptLibraryDateFormatterTests: XCTestCase {
  private let english = Locale(identifier: "en_US")

  func testFormatsReceiptDateWithYear() {
    XCTAssertEqual(
      ReceiptLibraryDateFormatter.formatted(localDate: "2026-08-10", locale: english),
      "August 10, 2026")
  }

  func testFormatsDateInSuppliedLocale() {
    XCTAssertEqual(
      ReceiptLibraryDateFormatter.formatted(
        localDate: "2026-08-10", locale: Locale(identifier: "fr_FR")),
      "10 août 2026")
  }

  func testRejectsInvalidDate() {
    XCTAssertNil(ReceiptLibraryDateFormatter.formatted(localDate: "2026-02-31"))
  }

  func testDayTitleLeavesOutYear() {
    XCTAssertEqual(
      ReceiptLibraryDateFormatter.dayTitle(localDate: "2026-08-10", locale: english), "Aug 10")
  }

  func testDayTitleIgnoresDeviceTimeZone() {
    XCTAssertEqual(
      ReceiptLibraryDateFormatter.dayTitle(localDate: "2026-08-01", locale: english), "Aug 1")
  }

  func testMonthTitleOmitsCurrentYear() {
    XCTAssertEqual(
      ReceiptLibraryDateFormatter.monthTitle(
        month: "2026-08", currentYear: 2026, locale: english),
      "August")
  }

  func testMonthTitleIncludesPastYear() {
    XCTAssertEqual(
      ReceiptLibraryDateFormatter.monthTitle(
        month: "2025-12", currentYear: 2026, locale: english),
      "December 2025")
  }
}
