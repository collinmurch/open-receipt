import Foundation

enum PaymentRequestDateFormatter {
  static func formatted(
    _ date: Date,
    relativeTo now: Date = Date(),
    calendar: Calendar = .current,
    locale: Locale = .current
  ) -> String {
    let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
      let weekday = date.formatted(base.weekday(.wide))
      let hour = base.hour(.defaultDigits(amPM: .abbreviated))
      var time = date.formatted(
        calendar.component(.minute, from: date) == 0 ? hour : hour.minute(.twoDigits))
      // "1pm" reads naturally in English; other languages keep their own time format.
      if locale.language.languageCode == .english {
        time = time.filter { !$0.isWhitespace }.lowercased(with: locale)
      }
      return "\(weekday) \(time)"
    }

    let day = base.month(.abbreviated).day()
    let isThisYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
    return date.formatted(isThisYear ? day : day.year())
  }
}
