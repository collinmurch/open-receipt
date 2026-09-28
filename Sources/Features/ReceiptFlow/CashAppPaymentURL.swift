import Foundation

enum CashAppPaymentURL {
  static func make(cashtag: String, amount: Double) -> URL? {
    let normalizedCashtag = Person.CashApp.normalizedCashtag(cashtag)
    let allowedCharacters = CharacterSet.alphanumerics.union(
      CharacterSet(charactersIn: "-_"))
    guard !normalizedCashtag.isEmpty,
      normalizedCashtag.unicodeScalars.allSatisfy(allowedCharacters.contains),
      amount.isFinite,
      amount > 0
    else { return nil }

    let formattedAmount = String(
      format: "%.2f",
      locale: Locale(identifier: "en_US_POSIX"),
      amount)
    var components = URLComponents()
    components.scheme = "https"
    components.host = "cash.app"
    components.path = "/$\(normalizedCashtag)/\(formattedAmount)"
    return components.url
  }
}
