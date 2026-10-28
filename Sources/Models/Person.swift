import Foundation

nonisolated struct Person: Codable, Equatable, Identifiable, Sendable {
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

    /// Trims what says where each method sends requests, and the "@" before a username and the
    /// "$" before a cashtag, removing any method left saying nothing.
    mutating func normalize() {
      if var venmo {
        venmo.recipient.value =
          venmo.recipient.kind == .username
          ? Venmo.normalizedUsername(venmo.recipient.value)
          : venmo.recipient.value.trimmed
        venmo.customUsername = venmo.customUsername.map(Venmo.normalizedUsername)
        if venmo.customUsername?.isEmpty == true { venmo.customUsername = nil }
        self.venmo = venmo.recipient.value.isEmpty ? nil : venmo
      }
      if var cashApp {
        cashApp.cashtag = CashApp.normalizedCashtag(cashApp.cashtag)
        self.cashApp = cashApp.cashtag.isEmpty ? nil : cashApp
      }
      if var iMessage {
        iMessage.recipient.value = iMessage.recipient.value.trimmed
        self.iMessage = iMessage.recipient.value.isEmpty ? nil : iMessage
      }
    }

    /// The method chosen for this person, when nothing says where it sends requests.
    var blankMethod: PaymentMethod? {
      switch defaultMethod {
      case .venmo: venmo == nil ? .venmo : nil
      case .cashApp: cashApp == nil ? .cashApp : nil
      case .iMessage: iMessage == nil ? .iMessage : nil
      case PaymentMethod.none?, nil: nil
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
      String(value.trimmed.trimmingPrefix("@"))
    }
  }

  struct CashApp: Codable, Equatable, Sendable {
    var cashtag: String

    var displayValue: String {
      "$\(Self.normalizedCashtag(cashtag))"
    }

    static func normalizedCashtag(_ value: String) -> String {
      let trimmed = value.trimmed
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

nonisolated extension Person.Venmo {
  init(username: String) {
    self.init(recipient: Recipient(kind: .username, value: username), customUsername: username)
  }
}

nonisolated extension [Person] {
  /// The saved person `participant` is: the one it links to, else the one for its contact, so a
  /// contact deleted and saved again keeps its receipts. Participants linked to no one, as receipts
  /// split before people were saved are, fall back to a unique name.
  func person(for participant: ReceiptParticipant) -> Person? {
    if let personID = participant.personID,
      let person = first(where: { $0.id == personID })
    {
      return person
    }

    if case .contact(let identifier) = participant.source,
      let contact = first(where: { $0.isContact(identifier) })
    {
      return contact
    }

    guard participant.personID == nil else { return nil }

    let matches = filter {
      $0.displayName.localizedCaseInsensitiveCompare(participant.displayName) == .orderedSame
    }
    return matches.count == 1 ? matches[0] : nil
  }
}

/// The contact that represents the person using the app. New receipts start with it.
nonisolated struct ReceiptOwner: Codable, Equatable, Sendable {
  var contactIdentifier: String
  var displayName: String
}
