import Foundation

nonisolated enum PaymentSettings {
  static let defaultMethodKey = "defaultPaymentMethod"
  static let initialDefaultMethod = PaymentMethod.venmo
}

nonisolated enum CurrencySettings {
  static let defaultCodeKey = "defaultCurrency"
  static let initialDefaultCode = "USD"

  /// The currency new receipts start with, or USD when none valid is stored.
  static func defaultCode(in defaults: UserDefaults = .standard) -> String {
    guard let code = defaults.string(forKey: defaultCodeKey), ReceiptValidator.isCurrencyCode(code)
    else { return initialDefaultCode }
    return code
  }
}

nonisolated enum AdjustmentSplitSettings {
  static let defaultMethodKey = "defaultAdjustmentSplitMethod"
  static let initialDefaultMethod = ReceiptAdjustmentSplitMethod.proportional

  /// How new receipts split tax and tip, or proportionally when none valid is stored.
  static func defaultMethod(in defaults: UserDefaults = .standard) -> ReceiptAdjustmentSplitMethod {
    defaults.string(forKey: defaultMethodKey).flatMap(ReceiptAdjustmentSplitMethod.init(rawValue:))
      ?? initialDefaultMethod
  }
}

/// What suggested tips are a percentage of.
nonisolated enum TipBase: String, CaseIterable, Codable, Identifiable, Sendable {
  case beforeTax
  case afterTax

  var id: Self { self }

  var title: String {
    switch self {
    case .beforeTax: "Before Tax"
    case .afterTax: "After Tax"
    }
  }
}

nonisolated enum TipSettings {
  static let percentageKeys = ["tipPercentageLow", "tipPercentageMiddle", "tipPercentageHigh"]
  static let initialPercentages = [18, 20, 22]
  static let percentageRange = 1...100
  static let baseKey = "tipBase"
  static let initialBase = TipBase.beforeTax

  /// What new receipts suggest tips as a percentage of, or the subtotal before tax when none valid
  /// is stored.
  static func base(in defaults: UserDefaults = .standard) -> TipBase {
    defaults.string(forKey: baseKey).flatMap(TipBase.init(rawValue:)) ?? initialBase
  }

  /// The tip percentages offered, lowest first and without repeats, using the initial one in
  /// place of any that isn't stored validly.
  static func percentages(in defaults: UserDefaults = .standard) -> [Int] {
    let percentages = zip(percentageKeys, initialPercentages).map { key, initial in
      (defaults.object(forKey: key) as? Int).flatMap { percentageRange.contains($0) ? $0 : nil }
        ?? initial
    }
    return Array(Set(percentages)).sorted()
  }
}

/// Whether reads use the sample receipt instead of Private Cloud Compute, so the simulator and
/// testers can read without PCC or its quota. Only testing builds can; it starts on in development.
nonisolated enum SampleReceipts {
  static let key = "TestingSampleReceipts"

  static var isEnabled: Bool {
    isEnabled(in: BuildChannel.current, defaults: .standard)
  }

  static func isEnabled(in channel: BuildChannel, defaults: UserDefaults) -> Bool {
    guard channel.isTesting else { return false }
    return defaults.object(forKey: key) as? Bool ?? isOnByDefault(in: channel)
  }

  static func isOnByDefault(in channel: BuildChannel) -> Bool {
    channel == .development
  }
}
