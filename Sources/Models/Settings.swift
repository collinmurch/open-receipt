import Foundation

enum PaymentSettings {
  static let defaultMethodKey = "defaultPaymentMethod"
  static let initialDefaultMethod = PaymentMethod.venmo
}

enum CurrencySettings {
  static let defaultCodeKey = "defaultCurrency"
  static let initialDefaultCode = "USD"

  /// The currency new receipts start with, or USD when none valid is stored.
  static func defaultCode(in defaults: UserDefaults = .standard) -> String {
    guard let code = defaults.string(forKey: defaultCodeKey), ReceiptValidator.isCurrencyCode(code)
    else { return initialDefaultCode }
    return code
  }
}

enum AdjustmentSplitSettings {
  static let defaultMethodKey = "defaultAdjustmentSplitMethod"
  static let initialDefaultMethod = ReceiptAdjustmentSplitMethod.proportional

  /// How new receipts split tax and tip, or proportionally when none valid is stored.
  static func defaultMethod(in defaults: UserDefaults = .standard) -> ReceiptAdjustmentSplitMethod {
    defaults.string(forKey: defaultMethodKey).flatMap(ReceiptAdjustmentSplitMethod.init(rawValue:))
      ?? initialDefaultMethod
  }
}
