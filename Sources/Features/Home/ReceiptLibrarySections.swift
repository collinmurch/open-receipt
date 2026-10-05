import Foundation

/// A month of receipts in the library.
struct ReceiptLibrarySection: Identifiable, Equatable {
  /// The month's first day as `yyyy-MM-dd`, which stays unique across calendars and eras.
  let id: String
  let title: String
  var receipts: [ReceiptSummary]
}

enum ReceiptLibrarySections {
  /// Groups receipts by month in `calendar`, newest first, by the day printed on them or else the
  /// day they were captured in `calendar`'s time zone.
  static func grouped(
    _ receipts: [ReceiptSummary],
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [ReceiptLibrarySection] {
    // Days are midnight UTC, so months are read from them in UTC as well.
    var monthCalendar = calendar
    monthCalendar.timeZone = .gmt
    let currentYear = calendar.dateComponents([.era, .year], from: now)
    let keyed = receipts.map { (day: day(for: $0, in: calendar.timeZone), receipt: $0) }
    let sorted = keyed.sorted {
      if $0.day != $1.day { return $0.day > $1.day }
      return $0.receipt.capturedAt > $1.receipt.capturedAt
    }

    var sections: [ReceiptLibrarySection] = []
    for entry in sorted {
      let month = monthCalendar.dateInterval(of: .month, for: entry.day)?.start ?? entry.day
      let id = ReceiptLocalDate.string(from: month)
      if sections.last?.id == id {
        sections[sections.count - 1].receipts.append(entry.receipt)
      } else {
        let year = monthCalendar.dateComponents([.era, .year], from: month)
        sections.append(
          ReceiptLibrarySection(
            id: id,
            title: ReceiptLibraryDateFormatter.monthTitle(
              of: month, in: monthCalendar, includesYear: year != currentYear),
            receipts: [entry.receipt]))
      }
    }
    return sections
  }

  /// The receipts in `sections` that satisfy `isIncluded`, dropping sections left empty.
  static func filtered(
    _ sections: [ReceiptLibrarySection],
    by isIncluded: (ReceiptSummary) -> Bool
  ) -> [ReceiptLibrarySection] {
    sections.compactMap { section in
      let receipts = section.receipts.filter(isIncluded)
      guard !receipts.isEmpty else { return nil }
      return ReceiptLibrarySection(id: section.id, title: section.title, receipts: receipts)
    }
  }

  private static func day(for receipt: ReceiptSummary, in timeZone: TimeZone) -> Date {
    receipt.localDate.flatMap(ReceiptLocalDate.date(from:))
      ?? ReceiptLocalDate.day(of: receipt.capturedAt, in: timeZone)
  }
}
