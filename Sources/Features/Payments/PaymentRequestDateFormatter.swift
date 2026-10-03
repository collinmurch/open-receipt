import Foundation

enum PaymentRequestDateFormatter {
  static func formatted(
    _ date: Date,
    relativeTo now: Date = Date(),
    calendar: Calendar = .current,
    locale: Locale = .current
  ) -> String {
    if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
      var weekdayStyle = Date.FormatStyle.dateTime.weekday(.wide)
      weekdayStyle.calendar = calendar
      weekdayStyle.timeZone = calendar.timeZone
      weekdayStyle.locale = locale
      let weekday = date.formatted(weekdayStyle)
      var timeStyle =
        calendar.component(.minute, from: date) == 0
        ? Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .abbreviated))
        : Date.FormatStyle.dateTime
          .hour(.defaultDigits(amPM: .abbreviated))
          .minute(.twoDigits)
      timeStyle.calendar = calendar
      timeStyle.timeZone = calendar.timeZone
      timeStyle.locale = locale
      var time = date.formatted(timeStyle)
      // "1pm" reads naturally in English; other languages keep their own time format.
      if locale.language.languageCode == .english {
        time = time.filter { !$0.isWhitespace }.lowercased(with: locale)
      }
      return "\(weekday) \(time)"
    }

    var style = Date.FormatStyle.dateTime
      .month(.abbreviated)
      .day()
    if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
      style = style.year()
    }
    style.calendar = calendar
    style.timeZone = calendar.timeZone
    style.locale = locale
    return date.formatted(style)
  }
}
