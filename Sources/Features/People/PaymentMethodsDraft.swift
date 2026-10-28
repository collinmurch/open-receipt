import Foundation

/// A person's payment methods as they're edited. Venmo and iMessage can use one of the contact's
/// phone numbers or email addresses, or what's typed in its place.
nonisolated struct PaymentMethodsDraft {
  var venmoRecipient: Person.Venmo.Recipient?
  var venmoUsername: String
  var cashtag: String
  var iMessageRecipient: Person.IMessage.Recipient?
  var customIMessageRecipient: String

  init(_ methods: Person.PaymentMethods) {
    let venmo = methods.venmo
    let venmoUsesUsername = venmo?.recipient.kind == .username
    venmoRecipient = venmoUsesUsername ? nil : venmo?.recipient
    venmoUsername =
      venmo?.customUsername ?? (venmoUsesUsername ? venmo?.recipient.value : nil) ?? ""
    cashtag = methods.cashApp?.cashtag ?? ""
    let iMessage = methods.iMessage
    let iMessageIsCustom = iMessage?.recipient.kind == .custom
    iMessageRecipient = iMessageIsCustom ? nil : iMessage?.recipient
    customIMessageRecipient = iMessageIsCustom ? iMessage?.recipient.value ?? "" : ""
  }

  /// Picks `contact`'s suggested recipients for the methods `saved` doesn't have and nothing has
  /// been picked or typed for.
  mutating func suggest(from contact: ContactSummary, unlessSetIn saved: Person.PaymentMethods) {
    if saved.venmo == nil, venmoRecipient == nil,
      Person.Venmo.normalizedUsername(venmoUsername).isEmpty
    {
      venmoRecipient = contact.defaultRecipient(Person.Venmo.Recipient.self)
    }
    if saved.iMessage == nil, iMessageRecipient == nil,
      customIMessageRecipient.trimmed.isEmpty
    {
      iMessageRecipient = contact.defaultRecipient(Person.IMessage.Recipient.self)
    }
  }

  /// Whether nothing has been picked or typed for `method`, so it has nowhere to send requests.
  func isBlank(_ method: PaymentMethod) -> Bool {
    switch method {
    case .venmo:
      venmoRecipient == nil && Person.Venmo.normalizedUsername(venmoUsername).isEmpty
    case .cashApp:
      Person.CashApp.normalizedCashtag(cashtag).isEmpty
    case .iMessage:
      iMessageRecipient == nil
        && customIMessageRecipient.trimmed.isEmpty
    case .none:
      false
    }
  }

  /// Writes the edited methods into `methods`, removing those left blank.
  func apply(to methods: inout Person.PaymentMethods) {
    methods.venmo =
      venmoRecipient.map { .init(recipient: $0, customUsername: venmoUsername) }
      ?? .init(username: venmoUsername)
    methods.cashApp = .init(cashtag: cashtag)
    methods.iMessage = .init(
      recipient: iMessageRecipient ?? .init(kind: .custom, value: customIMessageRecipient))
    methods.normalize()
  }
}
