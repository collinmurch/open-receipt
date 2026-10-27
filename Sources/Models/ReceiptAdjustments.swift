import Foundation

enum ReceiptTotalAdjustment: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case tax
  case tip
  case savings

  /// The adjustments a receipt asks about after a read that didn't find them. Savings aren't
  /// asked about, since most receipts have none.
  static let confirmable: [ReceiptTotalAdjustment] = [.tax, .tip]

  var id: Self { self }

  /// The order the adjustments are listed in when a tip is suggested on `tipBase`: the tip above
  /// tax for a tip before tax, and savings last.
  static func order(tipBase: TipBase) -> [ReceiptTotalAdjustment] {
    tipBase == .beforeTax ? [.tip, .tax, .savings] : [.tax, .tip, .savings]
  }

  /// `order` when it lists every adjustment once, or `nil` when it doesn't.
  static func validOrder(_ order: [ReceiptTotalAdjustment]) -> [ReceiptTotalAdjustment]? {
    order.count == allCases.count && Set(order) == Set(allCases) ? order : nil
  }

  var title: String {
    switch self {
    case .tax: "Tax"
    case .tip: "Tip"
    case .savings: "Savings"
    }
  }

  /// How the adjustment moves the total: savings are subtracted, tax and tip are added.
  var sign: Double {
    self == .savings ? -1 : 1
  }

  /// `amount` as it moves the total, or back from that: savings change sign.
  func signed(_ amount: Double) -> Double {
    amount == 0 ? 0 : amount * sign
  }
}

enum ReceiptAdjustmentSplitMethod: String, CaseIterable, Codable, Identifiable, Sendable {
  case proportional
  case even

  var id: Self { self }

  var title: String {
    switch self {
    case .proportional: "Proportionally"
    case .even: "Evenly"
    }
  }
}
