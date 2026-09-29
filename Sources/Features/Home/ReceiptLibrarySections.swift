import Foundation

/// A month of receipts in the library.
struct ReceiptLibrarySection: Identifiable, Equatable {
  /// The month as `yyyy-MM`.
  let id: String
  let title: String
  let receipts: [ReceiptSummary]
}

enum ReceiptLibrarySections {
  /// Groups receipts by the month printed on them, newest first, falling back to when they were captured.
  static func grouped(
    _ receipts: [ReceiptSummary],
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [ReceiptLibrarySection] {
    let currentYear = calendar.component(.year, from: now)
    let keyed = receipts.map { (day: day(for: $0, calendar: calendar), receipt: $0) }
    let sorted = keyed.sorted {
      if $0.day != $1.day { return $0.day > $1.day }
      return $0.receipt.capturedAt > $1.receipt.capturedAt
    }

    var sections: [ReceiptLibrarySection] = []
    for entry in sorted {
      let month = String(entry.day.prefix(7))
      if let last = sections.last, last.id == month {
        sections[sections.count - 1] = ReceiptLibrarySection(
          id: month, title: last.title, receipts: last.receipts + [entry.receipt])
      } else {
        sections.append(
          ReceiptLibrarySection(
            id: month,
            title: ReceiptLibraryDateFormatter.monthTitle(month: month, currentYear: currentYear)
              ?? month,
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

  private static func day(for receipt: ReceiptSummary, calendar: Calendar) -> String {
    if let date = receipt.localDate.flatMap(ReceiptLocalDate.date(from:)) {
      return ReceiptLocalDate.string(from: date)
    }
    return ReceiptLocalDate.string(from: receipt.capturedAt, in: calendar)
  }
}
