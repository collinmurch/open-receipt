import Contacts

nonisolated struct ContactSummary: Identifiable, Sendable, Equatable {
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
}

nonisolated extension Person.PaymentMethods {
  /// Sends Venmo and iMessage requests to `contact`'s suggested recipient where neither says
  /// where to send them, returning whether either changed.
  mutating func adoptRecipients(of contact: ContactSummary) -> Bool {
    let original = self
    if venmo == nil {
      venmo = contact.defaultRecipient(Person.Venmo.Recipient.self).map { .init(recipient: $0) }
    }
    if iMessage == nil {
      iMessage = contact.defaultRecipient(Person.IMessage.Recipient.self).map {
        .init(recipient: $0)
      }
    }
    return self != original
  }
}

nonisolated extension ReceiptOwner {
  init(_ contact: ContactSummary) {
    self.init(contactIdentifier: contact.identifier, displayName: contact.displayName)
  }
}

/// A payment recipient that can be one of a contact's phone numbers or email addresses.
nonisolated protocol ContactRecipient: Hashable, Identifiable {
  static func phoneNumber(_ value: String) -> Self
  static func emailAddress(_ value: String) -> Self
  var displayValue: String { get }
}

nonisolated extension Person.Venmo.Recipient: ContactRecipient {
  static func phoneNumber(_ value: String) -> Self {
    .init(kind: .phoneNumber, value: value)
  }

  static func emailAddress(_ value: String) -> Self {
    .init(kind: .emailAddress, value: value)
  }
}

nonisolated extension Person.IMessage.Recipient: ContactRecipient {
  static func phoneNumber(_ value: String) -> Self {
    .init(kind: .phoneNumber, value: value)
  }

  static func emailAddress(_ value: String) -> Self {
    .init(kind: .emailAddress, value: value)
  }
}
