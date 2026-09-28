import Foundation

enum ReceiptLibraryDateFormatter {
  static func formatted(localDate: String) -> String? {
    guard let (year, month, day) = components(localDate: localDate) else { return nil }
    return "\(months[month - 1]) \(day)\(ordinalSuffix(for: day)), \(year)"
  }

  /// The day without its year, for rows already grouped under a month.
  static func dayTitle(localDate: String) -> String? {
    guard let (_, month, day) = components(localDate: localDate) else { return nil }
    return "\(months[month - 1]) \(day)\(ordinalSuffix(for: day))"
  }

  /// The date as a zero-padded `yyyy-MM-dd`, which sorts chronologically as a string.
  static func normalizedDay(localDate: String) -> String? {
    guard let (year, month, day) = components(localDate: localDate) else { return nil }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  /// A `yyyy-MM` month as a section title, leaving out the year when it is the current one.
  static func monthTitle(month: String, currentYear: Int) -> String? {
    guard let (year, month, _) = components(localDate: "\(month)-01") else { return nil }
    return year == currentYear ? months[month - 1] : "\(months[month - 1]) \(year)"
  }

  private static func components(localDate: String) -> (year: Int, month: Int, day: Int)? {
    let parts = localDate.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-")
    guard parts.count == 3,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2]),
      months.indices.contains(month - 1),
      let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
    else { return nil }

    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard components.year == year, components.month == month, components.day == day else {
      return nil
    }
    return (year, month, day)
  }

  private static func ordinalSuffix(for day: Int) -> String {
    if 11...13 ~= day % 100 { return "th" }
    switch day % 10 {
    case 1: return "st"
    case 2: return "nd"
    case 3: return "rd"
    default: return "th"
    }
  }

  private static let months = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ]

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
  }()
}
