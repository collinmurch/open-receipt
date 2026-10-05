import Foundation

enum CashAppPaymentURL {
  static func make(cashtag: String, amount: Double) -> URL? {
    let normalizedCashtag = Person.CashApp.normalizedCashtag(cashtag)
    let allowedCharacters = CharacterSet.alphanumerics.union(
      CharacterSet(charactersIn: "-_"))
    guard !normalizedCashtag.isEmpty,
      normalizedCashtag.unicodeScalars.allSatisfy(allowedCharacters.contains),
      amount.isRequestable
    else { return nil }

    var components = URLComponents()
    components.scheme = "https"
    components.host = "cash.app"
    components.path = "/$\(normalizedCashtag)/\(amount.paymentLinkAmount)"
    return components.url
  }
}
