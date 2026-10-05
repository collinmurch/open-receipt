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

  /// Whether requests through this method can be in `currency`. Venmo and Cash App only move USD.
  func supports(currency: String) -> Bool {
    switch self {
    case .venmo, .cashApp:
      currency == "USD"
    case .iMessage, .none:
      true
    }
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
