import Foundation

struct Person: Codable, Equatable, Identifiable, Sendable {
  struct PaymentMethods: Codable, Equatable, Sendable {
    var defaultMethod: PaymentMethod?
    var venmo: Venmo?
    var cashApp: CashApp?
    var iMessage: IMessage?

    func destination(globalDefault: PaymentMethod) -> PaymentDestination? {
      switch defaultMethod ?? globalDefault {
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

  /// Whether this person is the contact `identifier` names. A person without a contact never is.
  func isContact(_ identifier: String?) -> Bool {
    contactIdentifier != nil && contactIdentifier == identifier
  }
}

extension Person.Venmo {
  init(username: String) {
    self.init(recipient: Recipient(kind: .username, value: username), customUsername: username)
  }
}

/// The contact that represents the person using the app. New receipts start with it.
struct ReceiptOwner: Codable, Equatable, Sendable {
  var contactIdentifier: String
  var displayName: String
}
