import Foundation

enum VenmoRequestURL {
  static func make(recipient: Person.Venmo.Recipient, amount: Double, note: String) -> URL? {
    guard let recipientValue = requestValue(for: recipient), amount.isRequestable else {
      return nil
    }

    var components = URLComponents()
    components.scheme = "venmo"
    components.host = "paycharge"
    components.queryItems = [
      URLQueryItem(name: "txn", value: "charge"),
      URLQueryItem(name: "recipients", value: recipientValue),
      URLQueryItem(name: "amount", value: amount.paymentLinkAmount),
      URLQueryItem(name: "note", value: note),
    ]
    return components.url
  }

  private static func requestValue(for recipient: Person.Venmo.Recipient) -> String? {
    let value: String? =
      switch recipient.kind {
      case .phoneNumber: recipient.normalizedUSPhoneNumber
      case .emailAddress: recipient.value.trimmingCharacters(in: .whitespacesAndNewlines)
      case .username: Person.Venmo.normalizedUsername(recipient.value)
      }
    return value?.isEmpty == false ? value : nil
  }
}
