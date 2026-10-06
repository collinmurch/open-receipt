import Contacts

struct ContactSummary: Identifiable, Sendable, Equatable {
  struct Value: Identifiable, Sendable, Hashable {
    var id: String { "\(label ?? ""):\(value)" }

    let label: String?
    let value: String
  }

  var id: String { identifier }

  let identifier: String
  let displayName: String
  let phoneNumbers: [Value]
  let emailAddresses: [Value]

  init(
    identifier: String,
    displayName: String,
    phoneNumbers: [Value] = [],
    emailAddresses: [Value] = []
  ) {
    self.identifier = identifier
    self.displayName = displayName
    self.phoneNumbers = Self.deduplicatedPhoneNumbers(phoneNumbers)
    self.emailAddresses = emailAddresses
  }

  private static func deduplicatedPhoneNumbers(_ phoneNumbers: [Value]) -> [Value] {
    var result: [Value] = []
    var indicesByNumber: [String: Int] = [:]

    for phoneNumber in phoneNumbers {
      let value = Value(
        label: normalizedPhoneLabel(phoneNumber.label),
        value: phoneNumber.value)
      let key = normalizedPhoneNumber(value.value)
      guard let index = indicesByNumber[key] else {
        indicesByNumber[key] = result.count
        result.append(value)
        continue
      }
      if isMobileLabel(value.label), !isMobileLabel(result[index].label) {
        result[index] = value
      }
    }
    return result
  }

  private static let mobileLabel = CNLabeledValue<NSString>.localizedString(
    forLabel: CNLabelPhoneNumberMobile)

  private static func normalizedPhoneLabel(_ label: String?) -> String? {
    guard let label else { return nil }
    return label.caseInsensitiveCompare("iPhone") == .orderedSame ? mobileLabel : label
  }

  private static func normalizedPhoneNumber(_ value: String) -> String {
    let digits = USPhoneNumber.nationalDigits(value)
    return digits.isEmpty ? value.lowercased() : digits
  }

  private static func isMobileLabel(_ label: String?) -> Bool {
    guard let label else { return false }
    return label.caseInsensitiveCompare("mobile") == .orderedSame
      || label.caseInsensitiveCompare(mobileLabel) == .orderedSame
  }

  /// The contact's first phone number, or its first email address when it has none.
  func defaultRecipient<Recipient: ContactRecipient>(_: Recipient.Type) -> Recipient? {
    if let phoneNumber = phoneNumbers.first {
      return Recipient.phoneNumber(phoneNumber.value)
    }
    return emailAddresses.first.map { Recipient.emailAddress($0.value) }
  }

  /// The payment methods this contact suggests for those `person` hasn't set.
  func paymentDefaults(for person: Person) -> ContactPaymentDefaults {
    ContactPaymentDefaults(
      venmo: person.paymentMethods.venmo == nil
        ? defaultRecipient(Person.Venmo.Recipient.self) : nil,
      iMessage: person.paymentMethods.iMessage == nil
        ? defaultRecipient(Person.IMessage.Recipient.self) : nil)
  }
}

struct ContactPaymentDefaults: Sendable, Equatable {
  let venmo: Person.Venmo.Recipient?
  let iMessage: Person.IMessage.Recipient?
}

extension Person {
  /// Fills in the payment methods suggested by the person's contact, returning whether any changed.
  mutating func adopt(_ defaults: ContactPaymentDefaults) -> Bool {
    var didChange = false
    if let recipient = defaults.venmo {
      paymentMethods.venmo = .init(recipient: recipient)
      didChange = true
    }
    if let recipient = defaults.iMessage {
      paymentMethods.iMessage = .init(recipient: recipient)
      didChange = true
    }
    return didChange
  }
}

extension ReceiptOwner {
  init(_ contact: ContactSummary) {
    self.init(contactIdentifier: contact.identifier, displayName: contact.displayName)
  }
}

/// A payment recipient that can be one of a contact's phone numbers or email addresses.
protocol ContactRecipient: Hashable, Identifiable {
  static func phoneNumber(_ value: String) -> Self
  static func emailAddress(_ value: String) -> Self
  var displayValue: String { get }
}

extension Person.Venmo.Recipient: ContactRecipient {
  static func phoneNumber(_ value: String) -> Self {
    .init(kind: .phoneNumber, value: value)
  }

  static func emailAddress(_ value: String) -> Self {
    .init(kind: .emailAddress, value: value)
  }
}

extension Person.IMessage.Recipient: ContactRecipient {
  static func phoneNumber(_ value: String) -> Self {
    .init(kind: .phoneNumber, value: value)
  }

  static func emailAddress(_ value: String) -> Self {
    .init(kind: .emailAddress, value: value)
  }
}
