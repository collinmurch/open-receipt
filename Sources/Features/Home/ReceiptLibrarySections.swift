import Foundation

/// A month of receipts in the history drawer.
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

  private static func day(for receipt: ReceiptSummary, calendar: Calendar) -> String {
    if let day = receipt.localDate.flatMap(ReceiptLibraryDateFormatter.normalizedDay) {
      return day
    }
    let components = calendar.dateComponents([.year, .month, .day], from: receipt.capturedAt)
    return String(
      format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
  }
}
