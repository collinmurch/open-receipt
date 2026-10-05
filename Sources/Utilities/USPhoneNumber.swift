enum USPhoneNumber {
  /// The digits of `value`, dropping a leading US country code of 1 from an 11-digit number.
  static func nationalDigits(_ value: String) -> String {
    let digits = String(value.unicodeScalars.filter { (48...57).contains($0.value) })
    return digits.count == 11 && digits.hasPrefix("1") ? String(digits.dropFirst()) : digits
  }

  /// The ten digits of a US phone number, dropping a leading country code of 1.
  static func digits(_ value: String) -> String? {
    let digits = nationalDigits(value)
    return digits.count == 10 ? digits : nil
  }

  /// Formats a US phone number as "(xxx) xxx-xxxx".
  static func formatted(_ value: String) -> String? {
    guard let digits = digits(value) else { return nil }
    return "(\(digits.prefix(3))) \(digits.dropFirst(3).prefix(3))-\(digits.suffix(4))"
  }
}
