import Foundation

enum VenmoRequestURL {
  static func make(recipient: Person.Venmo.Recipient, amount: Double, note: String) -> URL? {
    guard let recipientValue = requestValue(for: recipient),
      amount.isFinite,
      amount > 0
    else { return nil }

    var components = URLComponents()
    components.scheme = "venmo"
    components.host = "paycharge"
    components.queryItems = [
      URLQueryItem(name: "txn", value: "charge"),
      URLQueryItem(name: "recipients", value: recipientValue),
      URLQueryItem(
        name: "amount",
        value: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), amount)),
      URLQueryItem(name: "note", value: note),
    ]
    return components.url
  }

  private static func requestValue(for recipient: Person.Venmo.Recipient) -> String? {
    let value = recipient.value.trimmingCharacters(in: .whitespacesAndNewlines)
    switch recipient.kind {
    case .phoneNumber:
      return recipient.normalizedUSPhoneNumber
    case .emailAddress:
      return value.isEmpty ? nil : value
    case .username:
      let username = String(value.trimmingPrefix("@"))
      return username.isEmpty ? nil : username
    }
  }
}
