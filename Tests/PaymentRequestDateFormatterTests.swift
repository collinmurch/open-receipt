import XCTest

@testable import open_receipt

final class PaymentRequestDateFormatterTests: XCTestCase {
  func testFormatsWholeHourInCurrentWeekWithoutMinutes() throws {
    let calendar = testCalendar
    let now = try date(2026, 9, 18, 16, 0, calendar: calendar)
    let requestedAt = try date(2026, 9, 15, 13, 0, calendar: calendar)

    XCTAssertEqual(
      PaymentRequestDateFormatter.formatted(
        requestedAt,
        relativeTo: now,
        calendar: calendar,
        locale: testLocale),
      "Tuesday 1pm")
  }

  func testFormatsMinutesInCurrentWeek() throws {
    let calendar = testCalendar
    let now = try date(2026, 9, 18, 16, 0, calendar: calendar)
    let requestedAt = try date(2026, 9, 15, 13, 30, calendar: calendar)

    XCTAssertEqual(
      PaymentRequestDateFormatter.formatted(
        requestedAt,
        relativeTo: now,
        calendar: calendar,
        locale: testLocale),
      "Tuesday 1:30pm")
  }

  func testFormatsDateOutsideCurrentWeek() throws {
    let calendar = testCalendar
    let now = try date(2026, 9, 18, 16, 0, calendar: calendar)
    let requestedAt = try date(2026, 9, 8, 13, 0, calendar: calendar)

    XCTAssertEqual(
      PaymentRequestDateFormatter.formatted(
        requestedAt,
        relativeTo: now,
        calendar: calendar,
        locale: testLocale),
      "Sep 8")
  }

  func testIncludesYearOutsideCurrentYear() throws {
    let calendar = testCalendar
    let now = try date(2026, 9, 18, 16, 0, calendar: calendar)
    let requestedAt = try date(2025, 12, 8, 13, 0, calendar: calendar)

    XCTAssertEqual(
      PaymentRequestDateFormatter.formatted(
        requestedAt,
        relativeTo: now,
        calendar: calendar,
        locale: testLocale),
      "Dec 8, 2025")
  }

  private var testCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = testLocale
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    calendar.firstWeekday = 1
    return calendar
  }

  private var testLocale: Locale {
    Locale(identifier: "en_US")
  }

  private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    _ minute: Int,
    calendar: Calendar
  ) throws -> Date {
    try XCTUnwrap(
      calendar.date(
        from: DateComponents(
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute)))
  }
}
