import Foundation

nonisolated enum ReceiptTotalAdjustment: String, CaseIterable, Codable, Hashable, Identifiable,
  Sendable
{
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

  /// `amount` as it moves the total, or back from that: savings are subtracted, tax and tip are
  /// added.
  func signed(_ amount: Money) -> Money {
    self == .savings ? -amount : amount
  }
}

nonisolated struct ReceiptTotalAdjustments: Equatable, Sendable {
  private var amounts: [ReceiptTotalAdjustment: Money]

  init(tax: Money = 0, tip: Money = 0, savings: Money = 0) {
    amounts = [:]
    if tax != 0 { amounts[.tax] = tax }
    if tip != 0 { amounts[.tip] = tip }
    if savings != 0 { amounts[.savings] = savings }
  }

  subscript(_ adjustment: ReceiptTotalAdjustment) -> Money? {
    get { amounts[adjustment] }
    set { amounts[adjustment] = newValue }
  }

  var isEmpty: Bool {
    amounts.isEmpty
  }

  func contains(_ adjustment: ReceiptTotalAdjustment) -> Bool {
    amounts[adjustment] != nil
  }

  mutating func add(_ adjustment: ReceiptTotalAdjustment) {
    if amounts[adjustment] == nil {
      amounts[adjustment] = 0
    }
  }

  mutating func remove(_ adjustment: ReceiptTotalAdjustment) {
    amounts[adjustment] = nil
  }

  /// The amount `adjustment` adds to the total, negative for savings.
  func signedAmount(of adjustment: ReceiptTotalAdjustment) -> Money {
    adjustment.signed(amounts[adjustment] ?? .zero)
  }
}

nonisolated enum ReceiptAdjustmentSplitMethod: String, CaseIterable, Codable, Identifiable, Sendable
{
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
