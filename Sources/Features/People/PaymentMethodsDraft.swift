import Foundation

/// A person's payment methods as they're edited. Venmo and iMessage can use one of the contact's
/// phone numbers or email addresses, or what's typed in its place.
struct PaymentMethodsDraft {
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
      customIMessageRecipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      iMessageRecipient = contact.defaultRecipient(Person.IMessage.Recipient.self)
    }
  }

  /// Writes the edited methods into `methods`, removing those left blank.
  func apply(to methods: inout Person.PaymentMethods) {
    let username = Person.Venmo.normalizedUsername(venmoUsername)
    if let venmoRecipient {
      methods.venmo = .init(
        recipient: venmoRecipient, customUsername: username.isEmpty ? nil : username)
    } else {
      methods.venmo = username.isEmpty ? nil : .init(username: username)
    }
    let cashtag = Person.CashApp.normalizedCashtag(cashtag)
    methods.cashApp = cashtag.isEmpty ? nil : .init(cashtag: cashtag)
    if let iMessageRecipient {
      methods.iMessage = .init(recipient: iMessageRecipient)
    } else {
      let recipient = customIMessageRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
      methods.iMessage =
        recipient.isEmpty ? nil : .init(recipient: .init(kind: .custom, value: recipient))
    }
  }
}
