import Foundation

/// An exact decimal amount of money, such as 12.34. Its currency is the receipt's, kept beside
/// it, so changing a receipt's currency changes no amount.
public nonisolated struct Money: Hashable, Comparable, Sendable {
  public static let zero = Money(Decimal.zero)

  /// The amount, compacted so equal amounts are stored alike.
  public let decimal: Decimal

  public init(_ decimal: Decimal) {
    var decimal = decimal
    NSDecimalCompact(&decimal)
    self.decimal = decimal
  }

  /// The decimal `value` stands for, read at the 15 significant digits a `Double` holds
  /// faithfully, such as 0.3 for 0.1 + 0.2. `nil` when `value` isn't a finite amount.
  public init?(_ value: Double) {
    guard value.isFinite else { return nil }
    self.init(String(format: "%.15g", locale: Self.posix, value))
  }

  /// The amount `text` writes in plain or exponent notation, such as "12.34" or "1e-05", or `nil`
  /// when it isn't a finite decimal.
  public init?(_ text: String) {
    guard text.wholeMatch(of: /[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/) != nil,
      let decimal = Decimal(string: text, locale: Self.posix), !decimal.isNaN
    else { return nil }
    self.init(decimal)
  }

  /// `units` of the place `places` digits after the decimal point, such as 1.25 for 125 units at
  /// 2 places.
  public init(units: Int, places: Int) {
    self.init(
      Decimal(
        sign: units < 0 ? .minus : .plus, exponent: -places, significand: Decimal(units.magnitude)
      ))
  }

  /// The amount in units of the place `places` digits after the decimal point, with halves
  /// rounded away from zero, such as 101 for 1.005 at 2 places. `nil` when that's too many units
  /// to count.
  public func units(places: Int) -> Int? {
    let rounded = rounded(places: places).decimal
    let units = Decimal(sign: rounded.sign, exponent: places, significand: rounded.magnitude)
    return Int(units.description)
  }

  /// The amount rounded to `places` digits after the decimal point, with halves rounded away from
  /// zero.
  public func rounded(places: Int) -> Money {
    var decimal = decimal
    var rounded = Decimal()
    NSDecimalRound(&rounded, &decimal, places, .plain)
    return Money(rounded)
  }

  /// The part of `whole` the amount is, such as 0.25 for 1 out of 4, for drawing and comparing
  /// proportions.
  public func fraction(of whole: Money) -> Double {
    NSDecimalNumber(decimal: decimal / whole.decimal).doubleValue
  }

  public var magnitude: Money {
    Money(decimal.magnitude)
  }

  public func formatted(_ style: Decimal.FormatStyle.Currency) -> String {
    decimal.formatted(style)
  }

  public static func + (lhs: Money, rhs: Money) -> Money {
    Money(lhs.decimal + rhs.decimal)
  }

  public static func - (lhs: Money, rhs: Money) -> Money {
    Money(lhs.decimal - rhs.decimal)
  }

  public static prefix func - (amount: Money) -> Money {
    Money(-amount.decimal)
  }

  public static func += (lhs: inout Money, rhs: Money) {
    lhs = lhs + rhs
  }

  public static func -= (lhs: inout Money, rhs: Money) {
    lhs = lhs - rhs
  }

  /// `amount` scaled by `factor`, such as a percentage of it, with `factor` read the way
  /// `init(_:)` reads a `Double`. A factor that isn't finite scales it to zero. The result isn't
  /// rounded.
  public static func * (amount: Money, factor: Double) -> Money {
    Money(amount.decimal * (Money(factor) ?? .zero).decimal)
  }

  /// `amount` divided into `count` equal parts. The result isn't rounded.
  public static func / (amount: Money, count: Int) -> Money {
    precondition(count != 0, "An amount can't be divided into no parts.")
    return Money(amount.decimal / Decimal(count))
  }

  public static func < (lhs: Money, rhs: Money) -> Bool {
    lhs.decimal < rhs.decimal
  }

  private static let posix = Locale(identifier: "en_US_POSIX")
}

nonisolated extension Money: CustomStringConvertible {
  /// The amount in plain decimal notation, such as "12.34" or "-0.00001".
  public var description: String {
    decimal.description
  }
}

nonisolated extension Money: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
  public init(integerLiteral value: Int) {
    self.init(Decimal(value))
  }

  /// The amount the literal writes, read the way `init(_:)` reads a `Double`, so 0.1 is exactly
  /// a tenth.
  public init(floatLiteral value: Double) {
    guard let amount = Money(value) else { preconditionFailure("\(value) isn't an amount.") }
    self = amount
  }
}

nonisolated extension Double {
  /// The nearest `Double` to `amount`, for drawing and comparing proportions.
  public init(_ amount: Money) {
    self = NSDecimalNumber(decimal: amount.decimal).doubleValue
  }
}

nonisolated extension Money: Codable {
  /// Reads the amount from a number, digit for digit.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let decimal = try container.decode(Decimal.self)
    guard !decimal.isNaN else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an amount.")
    }
    self.init(decimal)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(decimal)
  }
}
