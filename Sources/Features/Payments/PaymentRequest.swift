import Foundation

/// A payment request ready to open.
nonisolated struct PaymentRequest {
  enum Action {
    case openURL(URL)
    case compose(recipient: String, body: String)
  }

  let method: PaymentMethod
  let amount: Money
  let currency: String
  let action: Action

  /// The request's action and amount. The share's payment caption already names the method.
  var title: String {
    let amount = amount.formatted(.currency(code: currency))
    return method == .cashApp ? "Open \(amount)" : "Request \(amount)"
  }

  var systemImage: String {
    method == .iMessage ? "message.fill" : "arrow.up.right"
  }

  /// The note attached to requests for a receipt from `merchantName`.
  static func note(merchantName: String) -> String {
    let merchant = merchantName.trimmed
    return merchant.isEmpty ? "Open Receipt split" : "Open Receipt split for: \(merchant)"
  }

  /// A Venmo charge of `amount` to `recipient`, or `nil` when the recipient can't receive one.
  static func venmoURL(recipient: Person.Venmo.Recipient, amount: Money, note: String) -> URL? {
    let value: String? =
      switch recipient.kind {
      case .phoneNumber: recipient.normalizedUSPhoneNumber
      case .emailAddress: recipient.value.trimmed
      case .username: Person.Venmo.normalizedUsername(recipient.value)
      }
    guard let value, !value.isEmpty else { return nil }

    var components = URLComponents()
    components.scheme = "venmo"
    components.host = "paycharge"
    components.queryItems = [
      URLQueryItem(name: "txn", value: "charge"),
      URLQueryItem(name: "recipients", value: value),
      URLQueryItem(name: "amount", value: linkAmount(amount)),
      URLQueryItem(name: "note", value: note),
    ]
    // Venmo reads a "+" in the query as a space.
    components.percentEncodedQuery = components.percentEncodedQuery?.replacing("+", with: "%2B")
    return components.url
  }

  /// A Cash App payment of `amount` to `cashtag`, or `nil` when the cashtag can't make a link.
  static func cashAppURL(cashtag: String, amount: Money) -> URL? {
    let cashtag = Person.CashApp.normalizedCashtag(cashtag)
    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    guard !cashtag.isEmpty, cashtag.unicodeScalars.allSatisfy(allowedCharacters.contains)
    else { return nil }

    var components = URLComponents()
    components.scheme = "https"
    components.host = "cash.app"
    components.path = "/$\(cashtag)/\(linkAmount(amount))"
    return components.url
  }

  /// A message asking for `amount`, followed by `note`, or `nil` when `currency` isn't a currency
  /// code.
  static func messageBody(
    amount: Money,
    currency: String,
    note: String,
    locale: Locale = .autoupdatingCurrent
  ) -> String? {
    guard ReceiptValidator.isCurrencyCode(currency) else { return nil }
    let request =
      "Could you pay me \(amount.formatted(.currency(code: currency).locale(locale))) when you get a chance?"
    let note = note.trimmed
    return note.isEmpty ? request : "\(request) \(note)"
  }

  /// `amount` with two decimal places and a period, as payment links expect in every locale.
  private static func linkAmount(_ amount: Money) -> String {
    amount.decimal.formatted(
      .number.precision(.fractionLength(2)).grouping(.never).locale(
        Locale(identifier: "en_US_POSIX")))
  }
}

/// What can be requested of someone besides the owner for their share of a receipt.
nonisolated enum PaymentRequestState {
  case ready(PaymentRequest)
  /// Their share can be requested once they have a payment method.
  case needsPaymentMethod
  /// Their share can't be requested, with why when there's something to say.
  case unavailable(String?)

  /// The request for `share` through `destination`, noting `note`.
  init(
    share: ReceiptParticipantShare,
    destination: PaymentDestination?,
    currency: String,
    note: String
  ) {
    let name = share.participant.displayName
    let amount = share.total
    guard amount > 0 else {
      self = .unavailable(
        amount < 0
          ? "You owe \(name) \((-amount).formatted(.currency(code: currency)))."
          : "Nothing to request from \(name).")
      return
    }
    guard let destination else {
      self = .needsPaymentMethod
      return
    }
    if let reason = destination.method.unsupportedCurrencyReason(currency) {
      self = .unavailable(reason)
      return
    }
    let action: PaymentRequest.Action? =
      switch destination {
      case .venmo(let recipient):
        PaymentRequest.venmoURL(recipient: recipient, amount: amount, note: note)
          .map(PaymentRequest.Action.openURL)
      case .cashApp(let cashApp):
        PaymentRequest.cashAppURL(cashtag: cashApp.cashtag, amount: amount)
          .map(PaymentRequest.Action.openURL)
      case .iMessage(let recipient):
        PaymentRequest.messageBody(amount: amount, currency: currency, note: note).map {
          .compose(recipient: recipient.value, body: $0)
        }
      }
    guard let action else {
      self = .unavailable(nil)
      return
    }
    self = .ready(
      PaymentRequest(method: destination.method, amount: amount, currency: currency, action: action)
    )
  }
}
