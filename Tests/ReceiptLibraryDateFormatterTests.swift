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

  func testFormatsDateInLocaleCalendar() {
    let date = ReceiptLibraryDateFormatter.formatted(
      localDate: "2026-08-10", locale: Locale(identifier: "th_TH@calendar=buddhist"))

    XCTAssertEqual(date?.contains("2569"), true)
  }

  func testMonthTitleOmitsYearWhenAsked() {
    XCTAssertEqual(
      ReceiptLibraryDateFormatter.monthTitle(
        of: augustFirst, in: ReceiptLocalDate.calendar, includesYear: false, locale: english),
      "August")
  }

  func testMonthTitleIncludesYearWhenAsked() {
    XCTAssertEqual(
      ReceiptLibraryDateFormatter.monthTitle(
        of: augustFirst, in: ReceiptLocalDate.calendar, includesYear: true, locale: english),
      "August 2026")
  }

  private var augustFirst: Date {
    ReceiptLocalDate.date(from: "2026-08-01")!
  }
}
