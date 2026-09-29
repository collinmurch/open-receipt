import Foundation

enum ReceiptTotalAdjustment: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case tax
  case tip
  case savings

  var id: Self { self }

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
