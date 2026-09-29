import Foundation

/// A payment request ready to open, for a final share that has somewhere to send it.
struct PreparedPaymentRequest: Equatable {
  enum Action: Equatable {
    case openURL(URL)
    case compose(recipient: String, body: String)
  }

  let method: PaymentMethod
  let amount: Double
  let currency: String
  let action: Action

  /// Fails for the receipt's owner, an unfinished split, a receipt not in USD, or a person
  /// without a payment method.
  init?(
    share: ReceiptParticipantShare,
    destination: PaymentDestination?,
    currency: String,
    note: String,
    isSplitComplete: Bool
  ) {
    guard isSplitComplete,
      currency == "USD",
      !share.participant.source.isCurrentUser,
      let destination
    else { return nil }

    let action: Action
    switch destination {
    case .venmo(let recipient):
      guard let url = VenmoRequestURL.make(recipient: recipient, amount: share.total, note: note)
      else { return nil }
      action = .openURL(url)
    case .cashApp(let cashApp):
      guard let url = CashAppPaymentURL.make(cashtag: cashApp.cashtag, amount: share.total)
      else { return nil }
      action = .openURL(url)
    case .iMessage(let recipient):
      guard let body = IMessageRequest.body(amount: share.total, currency: currency, context: note)
      else { return nil }
      action = .compose(recipient: recipient.value, body: body)
    }

    self.method = destination.method
    self.amount = share.total
    self.currency = currency
    self.action = action
  }

  var title: String {
    let amount = amount.formatted(.currency(code: currency))
    switch method {
    case .cashApp:
      return "Open \(amount) in Cash App"
    case .venmo, .iMessage:
      return "Request \(amount) in \(method.title)"
    case .none:
      return "Request \(amount)"
    }
  }

  var systemImage: String {
    method == .iMessage ? "message.fill" : "arrow.up.right"
  }

  /// The note attached to requests for a receipt from `merchantName`.
  static func note(merchantName: String) -> String {
    let merchant = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    return merchant.isEmpty ? "Open Receipt split" : "Open Receipt split for: \(merchant)"
  }
}
