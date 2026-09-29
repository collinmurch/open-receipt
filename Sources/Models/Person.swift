import Foundation

enum PaymentMethod: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case venmo
  case cashApp
  case iMessage
  case none

  var id: Self { self }

  var title: String {
    switch self {
    case .venmo:
      "Venmo"
    case .cashApp:
      "Cash App"
    case .iMessage:
      "iMessage"
    case .none:
      "None"
    }
  }

  var iconAssetName: String? {
    switch self {
    case .venmo:
      "PaymentMethods/venmo"
    case .cashApp:
      "PaymentMethods/cashApp"
    case .iMessage:
      "PaymentMethods/iMessage"
    case .none:
      nil
    }
  }
}

struct Person: Codable, Equatable, Identifiable, Sendable {
  struct PaymentMethods: Codable, Equatable, Sendable {
    var defaultMethod: PaymentMethod?
    var venmo: Venmo?
    var cashApp: CashApp?
    var iMessage: IMessage?

    init(
      defaultMethod: PaymentMethod? = nil,
      venmo: Venmo? = nil,
      cashApp: CashApp? = nil,
      iMessage: IMessage? = nil
    ) {
      self.defaultMethod = defaultMethod
      self.venmo = venmo
      self.cashApp = cashApp
      self.iMessage = iMessage
    }

    func resolvedMethod(globalDefault: PaymentMethod) -> PaymentMethod {
      defaultMethod ?? globalDefault
    }

    func destination(globalDefault: PaymentMethod) -> PaymentDestination? {
      switch resolvedMethod(globalDefault: globalDefault) {
      case .venmo:
        venmo.map { .venmo($0.recipient) }
      case .cashApp:
        cashApp.map(PaymentDestination.cashApp)
      case .iMessage:
        iMessage.map { .iMessage($0.recipient) }
      case .none:
        nil
      }
    }
  }

  struct Venmo: Codable, Equatable, Sendable {
    struct Recipient: Codable, Equatable, Hashable, Identifiable, Sendable {
      enum Kind: String, Codable, Sendable {
        case phoneNumber
        case emailAddress
        case username
      }

      var id: String { "\(kind.rawValue):\(value)" }

      var kind: Kind
      var value: String

      var displayValue: String {
        switch kind {
        case .phoneNumber:
          USPhoneNumber.formatted(value) ?? value
        case .emailAddress:
          value
        case .username:
          value.hasPrefix("@") ? value : "@\(value)"
        }
      }

      var normalizedUSPhoneNumber: String? {
        kind == .phoneNumber ? USPhoneNumber.digits(value) : nil
      }
    }

    var recipient: Recipient
    var customUsername: String? = nil

    init(recipient: Recipient, customUsername: String? = nil) {
      self.recipient = recipient
      self.customUsername = customUsername
    }

    init(username: String) {
      self.init(recipient: Recipient(kind: .username, value: username), customUsername: username)
    }

    /// `value` without surrounding whitespace or a leading "@".
    static func normalizedUsername(_ value: String) -> String {
      String(value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("@"))
    }
  }

  struct CashApp: Codable, Equatable, Sendable {
    var cashtag: String

    var displayValue: String {
      "$\(Self.normalizedCashtag(cashtag))"
    }

    static func normalizedCashtag(_ value: String) -> String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return String(trimmed.drop(while: { $0 == "$" }))
    }
  }

  struct IMessage: Codable, Equatable, Sendable {
    struct Recipient: Codable, Equatable, Hashable, Identifiable, Sendable {
      enum Kind: String, Codable, Sendable {
        case phoneNumber
        case emailAddress
        case custom
      }

      var id: String { "\(kind.rawValue):\(value)" }

      var kind: Kind
      var value: String

      var displayValue: String {
        guard kind != .emailAddress, !value.contains("@") else { return value }
        return USPhoneNumber.formatted(value) ?? value
      }
    }

    var recipient: Recipient
  }

  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  var lastIncludedAt: Date
  var displayName: String
  var contactIdentifier: String?
  var paymentMethods: PaymentMethods

  /// The order people are listed in: most recently included first, then by name.
  static func sortsBefore(_ lhs: Person, _ rhs: Person) -> Bool {
    if lhs.lastIncludedAt != rhs.lastIncludedAt {
      return lhs.lastIncludedAt > rhs.lastIncludedAt
    }
    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
  }
}

enum PaymentDestination: Equatable, Sendable {
  case venmo(Person.Venmo.Recipient)
  case cashApp(Person.CashApp)
  case iMessage(Person.IMessage.Recipient)

  var method: PaymentMethod {
    switch self {
    case .venmo:
      .venmo
    case .cashApp:
      .cashApp
    case .iMessage:
      .iMessage
    }
  }

  var displayValue: String {
    switch self {
    case .venmo(let recipient):
      recipient.displayValue
    case .cashApp(let cashApp):
      cashApp.displayValue
    case .iMessage(let recipient):
      recipient.displayValue
    }
  }
}

enum USPhoneNumber {
  /// The digits of `value`, dropping a leading US country code of 1 from an 11-digit number.
  static func nationalDigits(_ value: String) -> String {
    let digits = String(value.unicodeScalars.filter { (48...57).contains($0.value) })
    return digits.count == 11 && digits.hasPrefix("1") ? String(digits.dropFirst()) : digits
  }

  /// The ten digits of a US phone number, dropping a leading country code of 1.
  static func digits(_ value: String) -> String? {
    let digits = nationalDigits(value)
    return digits.count == 10 ? digits : nil
  }

  /// Formats a US phone number as "(xxx) xxx-xxxx".
  static func formatted(_ value: String) -> String? {
    guard let digits = digits(value) else { return nil }
    return "(\(digits.prefix(3))) \(digits.dropFirst(3).prefix(3))-\(digits.suffix(4))"
  }
}

/// The contact that represents the person using the app. New receipts start with it.
struct ReceiptOwner: Codable, Equatable, Sendable {
  var contactIdentifier: String
  var displayName: String
}

struct PeopleDocument: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 3

  var schemaVersion = currentSchemaVersion
  var people: [Person] = []
  var owner: ReceiptOwner?
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
