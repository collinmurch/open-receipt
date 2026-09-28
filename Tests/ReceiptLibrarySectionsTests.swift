#if !SWIFT_PACKAGE
  import XCTest
  @testable import open_receipt

  final class ReceiptLibrarySectionsTests: XCTestCase {
    private let calendar: Calendar = {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
      return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testGroupsReceiptsByPrintedMonth() {
      let sections = ReceiptLibrarySections.grouped(
        [receipt(localDate: "2026-08-10"), receipt(localDate: "2026-07-02")],
        now: now, calendar: calendar)

      XCTAssertEqual(sections.map(\.id), ["2026-08", "2026-07"])
    }

    func testOrdersSectionsNewestFirstRegardlessOfInputOrder() {
      let sections = ReceiptLibrarySections.grouped(
        [receipt(localDate: "2026-06-01"), receipt(localDate: "2026-09-01")],
        now: now, calendar: calendar)

      XCTAssertEqual(sections.map(\.id), ["2026-09", "2026-06"])
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

      XCTAssertEqual(sections.map(\.id), ["2026-05"])
    }

    func testFallsBackToCaptureDateForInvalidPrintedDate() {
      let captured = calendar.date(from: DateComponents(year: 2026, month: 3, day: 4)) ?? now

      let sections = ReceiptLibrarySections.grouped(
        [receipt(localDate: "2026-02-31", capturedAt: captured)], now: now, calendar: calendar)

      XCTAssertEqual(sections.map(\.id), ["2026-03"])
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

    func testReturnsNoSectionsForNoReceipts() {
      XCTAssertEqual(ReceiptLibrarySections.grouped([], now: now, calendar: calendar), [])
    }

    func testInitialsUseFirstTwoWords() {
      XCTAssertEqual(ReceiptMonogram.initials(for: "Juniper Market"), "JM")
    }

    func testInitialsUseSingleWord() {
      XCTAssertEqual(ReceiptMonogram.initials(for: "starbucks"), "S")
    }

    func testInitialsSkipPunctuation() {
      XCTAssertEqual(ReceiptMonogram.initials(for: "Trader Joe's #552"), "TJ")
    }

    func testInitialsSplitOnHyphen() {
      XCTAssertEqual(ReceiptMonogram.initials(for: "Chick-fil-A"), "CF")
    }

    func testInitialsReturnNilForBlankName() {
      XCTAssertNil(ReceiptMonogram.initials(for: "  "))
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
#endif
