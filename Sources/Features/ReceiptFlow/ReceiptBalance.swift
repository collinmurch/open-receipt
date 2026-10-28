import Foundation

/// How a receipt's amounts add up, in two steps: from the items to the printed subtotal, then from
/// the subtotal and its adjustments to the printed total.
///
/// Receipts take savings off in different places. Some print item prices with the savings already
/// taken off, some take them off before the subtotal, and others after it. The balance reads
/// savings the way that best explains the printed amounts, so a receipt that adds up on paper adds
/// up here too.
nonisolated struct ReceiptBalance: Equatable, Sendable {
  /// Where a receipt's savings were taken off.
  struct SavingsPlacement: Equatable, Sendable {
    /// Whether the item prices already have the savings taken off.
    var isInItems: Bool
    /// Whether the printed subtotal already has the savings taken off.
    var isInSubtotal: Bool

    /// Savings taken off after the subtotal, which is how the receipt's amounts are edited.
    static let afterSubtotal = SavingsPlacement(isInItems: false, isInSubtotal: false)

    fileprivate static let all = [
      afterSubtotal,
      SavingsPlacement(isInItems: true, isInSubtotal: false),
      SavingsPlacement(isInItems: false, isInSubtotal: true),
      SavingsPlacement(isInItems: true, isInSubtotal: true),
    ]

    fileprivate var assumptionCount: Int {
      (isInItems ? 1 : 0) + (isInSubtotal ? 1 : 0)
    }
  }

  let placement: SavingsPlacement
  /// What the items' line totals add up to.
  let itemsTotal: Money
  /// The subtotal printed on the receipt, or `nil` when it doesn't show one.
  let printedSubtotal: Money?
  /// The subtotal the items come to, with savings taken off where the receipt takes them off.
  /// `nil` when the receipt doesn't show a subtotal.
  let calculatedSubtotal: Money?
  /// The total the subtotal and adjustments come to, or the items and adjustments when the
  /// receipt doesn't show a subtotal.
  let calculatedTotal: Money
  /// How much the printed subtotal is over the items, negative when it's under.
  let subtotalDifference: Money
  /// How much the printed total is over the subtotal and adjustments, negative when it's under.
  let totalDifference: Money
  /// `subtotalDifference` and `totalDifference` in the currency's smallest unit, which is what
  /// the split shares out.
  let subtotalDifferenceUnits: Int
  let totalDifferenceUnits: Int

  /// Balances `input`, reading savings at `placement`, or wherever best explains the printed
  /// amounts when it's `nil`.
  init(_ input: ReceiptSplitInput, placement: SavingsPlacement? = nil) {
    if let placement {
      self.init(input, at: placement)
    } else {
      self.init(input) { _ in input }
    }
  }

  /// Balances `input` as `adjusted` changes it for each placement, reading savings wherever that
  /// best explains the printed amounts. It's for an amount that depends on where savings were
  /// taken off, such as a tip on the subtotal after them: each placement is judged with the
  /// amount it would give.
  init(
    _ input: ReceiptSplitInput,
    adjustedAt adjusted: (SavingsPlacement) -> ReceiptSplitInput
  ) {
    self = Self.placements(for: input).map { Self(adjusted($0), at: $0) }.min {
      $0.score < $1.score
    }!
  }

  private init(_ input: ReceiptSplitInput, at placement: SavingsPlacement) {
    let code = input.currency
    func units(_ amount: Money) -> Int { ReceiptCurrency.minorUnits(amount, code: code) }
    func amount(_ units: Int) -> Money { ReceiptCurrency.amount(minorUnits: units, code: code) }

    let amounts = Amounts(
      items: input.items.reduce(0) { $0 + units($1.lineTotal) },
      subtotal: input.subtotal > 0 ? units(input.subtotal) : nil,
      charges: units(input.adjustments[.tax] ?? 0) + units(input.adjustments[.tip] ?? 0),
      savings: units(input.adjustments[.savings] ?? 0),
      total: units(input.total))
    let steps = amounts.steps(at: placement)

    self.placement = placement
    itemsTotal = amount(amounts.items)
    printedSubtotal = amounts.subtotal.map(amount)
    calculatedSubtotal = steps.subtotal.map(amount)
    calculatedTotal = amount(steps.total)
    subtotalDifferenceUnits = amounts.subtotal.map { $0 - (steps.subtotal ?? $0) } ?? 0
    totalDifferenceUnits = amounts.total - steps.total
    subtotalDifference = amount(subtotalDifferenceUnits)
    totalDifference = amount(totalDifferenceUnits)
  }

  /// Where `input`'s savings could have been taken off. A receipt without a subtotal only shows
  /// whether they're in the item prices.
  private static func placements(for input: ReceiptSplitInput) -> [SavingsPlacement] {
    guard (input.adjustments[.savings] ?? 0) != 0 else { return [.afterSubtotal] }
    return input.subtotal > 0
      ? SavingsPlacement.all : SavingsPlacement.all.filter { $0.isInItems == $0.isInSubtotal }
  }

  /// How well the balance explains its receipt, lowest best: it leaves the fewest steps off, then
  /// assumes the least, then leaves the smallest differences.
  private var score: (Int, Int, Int) {
    let differences = [subtotalDifferenceUnits, totalDifferenceUnits]
    return (
      differences.filter { $0 != 0 }.count,
      placement.assumptionCount,
      differences.reduce(0) { $0 + abs($1) }
    )
  }

  var isBalanced: Bool {
    subtotalDifferenceUnits == 0 && totalDifferenceUnits == 0
  }

  /// Whether savings come off between the subtotal the receipt shows and its total. When they
  /// don't, they were already taken off above it.
  var subtractsSavingsFromSubtotal: Bool {
    subtractsSavingsFromSubtotal(at: placement)
  }

  /// Whether savings read at `placement` come off between the subtotal and the total.
  func subtractsSavingsFromSubtotal(at placement: SavingsPlacement) -> Bool {
    printedSubtotal == nil ? !placement.isInItems : !placement.isInSubtotal
  }

  /// Whether the split takes savings off the items, rather than finding them in the prices.
  var subtractsSavingsFromItems: Bool {
    !placement.isInItems
  }

  /// The subtotal the totals list shows: the printed one, or the items when there isn't one.
  var subtotal: Money {
    printedSubtotal ?? itemsTotal
  }

  /// A receipt's amounts in the currency's smallest unit.
  private struct Amounts {
    let items: Int
    let subtotal: Int?
    /// Tax and tip.
    let charges: Int
    let savings: Int
    let total: Int

    func steps(at placement: SavingsPlacement) -> (subtotal: Int?, total: Int) {
      guard let subtotal else {
        return (nil, items + charges - (placement.isInItems ? 0 : savings))
      }
      let calculatedSubtotal =
        items + (placement.isInItems ? savings : 0) - (placement.isInSubtotal ? savings : 0)
      return (calculatedSubtotal, subtotal + charges - (placement.isInSubtotal ? 0 : savings))
    }
  }
}
