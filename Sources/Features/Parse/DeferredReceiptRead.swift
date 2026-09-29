import Foundation

/// Wording for reads that stopped at the reading limit and start again on their own.
enum DeferredReceiptRead {
  /// Explains why a receipt wasn't read and when it will be.
  static func description(until date: Date, now: Date = Date()) -> String {
    "Today’s reading limit is reached. This receipt will be read automatically \(resumption(at: date, now: now))."
  }

  /// A short status for a receipt waiting to be read, such as "Reads after 3:00 PM".
  static func status(until date: Date, now: Date = Date()) -> String {
    "Reads \(resumption(at: date, now: now))"
  }

  /// When waiting reads resume, such as "after 3:00 PM" or "tomorrow".
  static func resumption(at date: Date, now: Date = Date()) -> String {
    guard date > now else { return "when reading is available" }
    if Calendar.current.isDate(date, inSameDayAs: now) {
      return "after \(date.formatted(date: .omitted, time: .shortened))"
    }
    return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
  }
}
