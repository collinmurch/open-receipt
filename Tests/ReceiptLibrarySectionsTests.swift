import XCTest

@testable import open_receipt

final class ReceiptLibrarySectionsTests: XCTestCase {
  private let calendar = ReceiptLocalDate.calendar

  private let now = Date(timeIntervalSince1970: 1_790_000_000)

  func testGroupsReceiptsByPrintedMonth() {
    let sections = ReceiptLibrarySections.grouped(
      [receipt(localDate: "2026-08-10"), receipt(localDate: "2026-07-02")],
      now: now, calendar: calendar)

    XCTAssertEqual(sections.map(\.id), ["2026-08-01", "2026-07-01"])
  }

  func testOrdersSectionsNewestFirstRegardlessOfInputOrder() {
    let sections = ReceiptLibrarySections.grouped(
      [receipt(localDate: "2026-06-01"), receipt(localDate: "2026-09-01")],
      now: now, calendar: calendar)

    XCTAssertEqual(sections.map(\.id), ["2026-09-01", "2026-06-01"])
  }

  func testOrdersReceiptsWithinMonthByDayDescending() {
    let early = receipt(localDate: "2026-08-02")
    let late = receipt(localDate: "2026-08-20")

    let sections = ReceiptLibrarySections.grouped([early, late], now: now, calendar: calendar)

    XCTAssertEqual(sections.first?.receipts.map(\.id), [late.id, early.id])
  }

  func testFallsBackToCaptureDateWithoutPrintedDate() {
    let captured = calendar.date(from: DateComponents(year: 2026, month: 5, day: 14)) ?? now

    let sections = ReceiptLibrarySections.grouped(
      [receipt(localDate: nil, capturedAt: captured)], now: now, calendar: calendar)

    XCTAssertEqual(sections.map(\.id), ["2026-05-01"])
  }

  func testFallsBackToCaptureDateForInvalidPrintedDate() {
    let captured = calendar.date(from: DateComponents(year: 2026, month: 3, day: 4)) ?? now

    let sections = ReceiptLibrarySections.grouped(
      [receipt(localDate: "2026-02-31", capturedAt: captured)], now: now, calendar: calendar)

    XCTAssertEqual(sections.map(\.id), ["2026-03-01"])
  }

  func testTitlesCurrentYearWithMonthOnly() {
    let sections = ReceiptLibrarySections.grouped(
      [receipt(localDate: "2026-08-10")], now: now, calendar: calendar)

    XCTAssertEqual(sections.first?.title, "August")
  }

  func testTitlesPastYearWithYear() {
    let sections = ReceiptLibrarySections.grouped(
      [receipt(localDate: "2025-08-10")], now: now, calendar: calendar)

    XCTAssertEqual(sections.first?.title, "August 2025")
  }

  func testGroupsAndTitlesMonthsInBuddhistCalendar() {
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = .gmt

    let sections = ReceiptLibrarySections.grouped(
      [receipt(localDate: "2025-08-10")], now: now, calendar: buddhist)

    XCTAssertEqual(sections.map(\.id), ["2025-08-01"])
    XCTAssertEqual(sections.first?.title.contains("2568"), true)
  }

  func testGroupsByMonthsOfIslamicCalendar() {
    var islamic = Calendar(identifier: .islamicUmmAlQura)
    islamic.timeZone = .gmt

    // Both days fall in the same Gregorian month but in different Islamic months.
    let sections = ReceiptLibrarySections.grouped(
      [receipt(localDate: "2026-08-02"), receipt(localDate: "2026-08-28")],
      now: now, calendar: islamic)

    XCTAssertEqual(sections.count, 2)
  }

  func testCaptureDayUsesCalendarTimeZone() {
    var newYork = Calendar(identifier: .gregorian)
    newYork.timeZone = TimeZone(identifier: "America/New_York")!
    // 2026-06-01 02:00 UTC is still May 31 in New York.
    let captured = Date(timeIntervalSince1970: 1_780_279_200)

    let sections = ReceiptLibrarySections.grouped(
      [receipt(localDate: nil, capturedAt: captured)], now: now, calendar: newYork)

    XCTAssertEqual(sections.map(\.id), ["2026-05-01"])
  }

  func testReturnsNoSectionsForNoReceipts() {
    XCTAssertEqual(ReceiptLibrarySections.grouped([], now: now, calendar: calendar), [])
  }

  func testFilteredKeepsMatchingReceiptsInOrder() {
    let early = receipt(localDate: "2026-08-02")
    let late = receipt(localDate: "2026-08-20")
    let sections = ReceiptLibrarySections.grouped([early, late], now: now, calendar: calendar)

    let filtered = ReceiptLibrarySections.filtered(sections) { _ in true }

    XCTAssertEqual(filtered, sections)
  }

  func testFilteredDropsEmptySections() {
    let august = receipt(localDate: "2026-08-10")
    let july = receipt(localDate: "2026-07-02")
    let sections = ReceiptLibrarySections.grouped([august, july], now: now, calendar: calendar)

    let filtered = ReceiptLibrarySections.filtered(sections) { $0.id == july.id }

    XCTAssertEqual(filtered.map(\.id), ["2026-07-01"])
    XCTAssertEqual(filtered.first?.receipts.map(\.id), [july.id])
  }

  func testFilteredKeepsSectionTitle() {
    let sections = ReceiptLibrarySections.grouped(
      [receipt(localDate: "2025-08-10")], now: now, calendar: calendar)

    let filtered = ReceiptLibrarySections.filtered(sections) { _ in true }

    XCTAssertEqual(filtered.first?.title, "August 2025")
  }

  private func receipt(localDate: String?, capturedAt: Date? = nil) -> ReceiptSummary {
    ReceiptSummary(
      id: UUID(),
      updatedAt: now,
      capturedAt: capturedAt ?? now,
      backgroundStyle: .blue,
      recognitionStatus: .succeeded,
      merchantName: "Juniper Market",
      localDate: localDate,
      total: 12,
      currency: "USD",
      isUnavailable: false,
      unavailableDescription: nil)
  }
}
