import Foundation

/// A receipt's printed `yyyy-MM-dd` day. Days are read and written in a fixed UTC calendar, so
/// the printed day never shifts with the device's time zone.
enum ReceiptLocalDate {
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  /// The start of the day `value` names, or nil when it isn't a real day. Month and day may be
  /// unpadded, and surrounding whitespace is ignored.
  static func date(from value: String) -> Date? {
    let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-")
    guard parts.count == 3,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2]),
      let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
    else { return nil }

    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard components.year == year, components.month == month, components.day == day else {
      return nil
    }
    return date
  }

  /// The day `date` falls on in `timeZone`, as a zero-padded `yyyy-MM-dd`, which sorts
  /// chronologically as a string. The day is always written in the Gregorian calendar.
  static func string(from date: Date, in timeZone: TimeZone = .gmt) -> String {
    var local = calendar
    local.timeZone = timeZone
    let components = local.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
  }

  /// The day `date` falls on in `timeZone`, as the start of that day in UTC, like `date(from:)`.
  static func day(of date: Date, in timeZone: TimeZone) -> Date {
    Self.date(from: string(from: date, in: timeZone)) ?? date
  }
}
