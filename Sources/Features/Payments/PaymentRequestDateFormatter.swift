import Foundation

enum PaymentRequestDateFormatter {
  static func formatted(
    _ date: Date,
    relativeTo now: Date = Date(),
    calendar: Calendar = .current,
    locale: Locale = .current
  ) -> String {
    let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    let timeText = { time(of: date, base: base, calendar: calendar, locale: locale) }
    if calendar.isDate(date, inSameDayAs: now) {
      return "today \(timeText())"
    }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
      calendar.isDate(date, inSameDayAs: yesterday)
    {
      return "yesterday \(timeText())"
    }
    if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
      return "\(date.formatted(base.weekday(.wide))) \(timeText())"
    }

    let day = base.month(.abbreviated).day()
    let isThisYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
    return date.formatted(isThisYear ? day : day.year())
  }

  private static func time(
    of date: Date,
    base: Date.FormatStyle,
    calendar: Calendar,
    locale: Locale
  ) -> String {
    let hour = base.hour(.defaultDigits(amPM: .abbreviated))
    let time = date.formatted(
      calendar.component(.minute, from: date) == 0 ? hour : hour.minute(.twoDigits))
    // "1pm" reads naturally in English; other languages keep their own time format.
    guard locale.language.languageCode == .english else { return time }
    return time.filter { !$0.isWhitespace }.lowercased(with: locale)
  }
}
