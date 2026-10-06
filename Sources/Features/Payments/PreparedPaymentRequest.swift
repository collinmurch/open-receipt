import Foundation

/// A payment request ready to open, for a final share that has somewhere to send it.
struct PreparedPaymentRequest {
  enum Action {
    case openURL(URL)
    case compose(recipient: String, body: String)
  }

  let method: PaymentMethod
  let amount: Double
  let currency: String
  let action: Action

  /// Fails for the receipt's owner, an unfinished split, a person without a payment method, or a
  /// currency the method can't request.
  init?(
    share: ReceiptParticipantShare,
    destination: PaymentDestination?,
    currency: String,
    note: String,
    isSplitComplete: Bool
  ) {
    guard !share.participant.source.isCurrentUser,
      Self.unavailableReason(
        share: share, destination: destination, currency: currency,
        isSplitComplete: isSplitComplete) == nil,
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

  /// Why `share` can't be requested, or `nil` when it can or is the owner's own share.
  static func unavailableReason(
    share: ReceiptParticipantShare,
    destination: PaymentDestination?,
    currency: String,
    isSplitComplete: Bool
  ) -> String? {
    guard !share.participant.source.isCurrentUser else { return nil }
    guard isSplitComplete else { return "Assign every item before you send requests." }
    guard let destination else {
      return "Add a payment method to request from \(share.participant.displayName)."
    }
    return destination.method.unsupportedCurrencyReason(currency)
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
