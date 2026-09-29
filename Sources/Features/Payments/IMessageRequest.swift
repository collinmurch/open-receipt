import Foundation

enum IMessageRequest {
  static func body(amount: Double, currency: String, context: String) -> String? {
    guard amount.isFinite, amount > 0, ReceiptValidator.isCurrencyCode(currency) else { return nil }
    let formattedAmount = amount.formatted(
      .currency(code: currency).locale(Locale(identifier: "en_US")))
    let normalizedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedContext.isEmpty else {
      return "Could you send me \(formattedAmount) with Apple Cash?"
    }
    return "Could you send me \(formattedAmount) with Apple Cash? \(normalizedContext)"
  }
}
