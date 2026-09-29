import Foundation

enum ReceiptLibraryDateFormatter {
  /// The printed date with its year, such as "August 10, 2026", for searching.
  static func formatted(localDate: String, locale: Locale = .current) -> String? {
    guard let date = ReceiptLocalDate.date(from: localDate) else { return nil }
    return date.formatted(style(locale).year().month(.wide).day())
  }

  /// The day without its year, for rows already grouped under a month.
  static func dayTitle(localDate: String, locale: Locale = .current) -> String? {
    guard let date = ReceiptLocalDate.date(from: localDate) else { return nil }
    return date.formatted(style(locale).month(.abbreviated).day())
  }

  /// A `yyyy-MM` month as a section title, leaving out the year when it is the current one.
  static func monthTitle(month: String, currentYear: Int, locale: Locale = .current) -> String? {
    guard let date = ReceiptLocalDate.date(from: "\(month)-01") else { return nil }
    let year = ReceiptLocalDate.calendar.component(.year, from: date)
    let monthStyle = style(locale).month(.wide)
    return date.formatted(year == currentYear ? monthStyle : monthStyle.year())
  }

  private static func style(_ locale: Locale) -> Date.FormatStyle {
    let calendar = ReceiptLocalDate.calendar
    return Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
  }
}
