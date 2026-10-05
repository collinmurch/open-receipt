import Foundation

/// Formats receipt days for the library. A printed day is a `yyyy-MM-dd` in UTC, so it is shown
/// in UTC to keep the device's time zone from moving it, and in the locale's own calendar.
enum ReceiptLibraryDateFormatter {
  /// A receipt's printed day with its year, such as "August 10, 2026".
  static func formatted(localDate: String, locale: Locale = .current) -> String? {
    guard let date = ReceiptLocalDate.date(from: localDate) else { return nil }
    return date.formatted(style(locale, calendar: locale.calendar).year().month(.wide).day())
  }

  /// The day without its year, for rows already grouped under a month.
  static func dayTitle(localDate: String, locale: Locale = .current) -> String? {
    guard let date = ReceiptLocalDate.date(from: localDate) else { return nil }
    return date.formatted(style(locale, calendar: locale.calendar).month(.abbreviated).day())
  }

  /// The month `day` falls in under `calendar`, as a section title. The year is left out when
  /// `includesYear` is false.
  static func monthTitle(
    of day: Date,
    in calendar: Calendar,
    includesYear: Bool,
    locale: Locale = .current
  ) -> String {
    let monthStyle = style(locale, calendar: calendar).month(.wide)
    return day.formatted(includesYear ? monthStyle.year() : monthStyle)
  }

  private static func style(_ locale: Locale, calendar: Calendar) -> Date.FormatStyle {
    Date.FormatStyle(locale: locale, calendar: calendar, timeZone: .gmt)
  }
}
