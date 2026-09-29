#if !SWIFT_PACKAGE
  import XCTest
  @testable import open_receipt

  final class ReceiptLocalDateTests: XCTestCase {
    func testReadsDayInUTC() throws {
      let date = try XCTUnwrap(ReceiptLocalDate.date(from: "2026-08-11"))
      let components = ReceiptLocalDate.calendar.dateComponents(
        [.year, .month, .day, .hour], from: date)

      XCTAssertEqual(components.year, 2026)
      XCTAssertEqual(components.month, 8)
      XCTAssertEqual(components.day, 11)
      XCTAssertEqual(components.hour, 0)
    }

    func testReadsUnpaddedDayWithWhitespace() {
      XCTAssertEqual(
        ReceiptLocalDate.date(from: " 2026-8-1 "), ReceiptLocalDate.date(from: "2026-08-01"))
    }

    func testRejectsDayPastEndOfMonth() {
      XCTAssertNil(ReceiptLocalDate.date(from: "2026-02-31"))
    }

    func testRejectsMonthOutOfRange() {
      XCTAssertNil(ReceiptLocalDate.date(from: "2026-13-01"))
    }

    func testRejectsMalformedValue() {
      XCTAssertNil(ReceiptLocalDate.date(from: "Aug 11, 2026"))
    }

    func testWritesZeroPaddedDay() throws {
      let date = try XCTUnwrap(
        ReceiptLocalDate.calendar.date(from: DateComponents(year: 2027, month: 2, day: 3)))

      XCTAssertEqual(ReceiptLocalDate.string(from: date), "2027-02-03")
    }
  }
#endif
