import Foundation

extension ReceiptDraft {
  var normalizedCurrency: String {
    ReceiptCurrency.normalized(currency)
  }

  /// The currency code amounts are formatted with while the entered code may be incomplete.
  var displayCurrency: String {
    ReceiptCurrency.displayCode(normalizedCurrency)
  }

  /// The values the split is worked out from.
  var splitInput: ReceiptSplitInput {
    ReceiptSplitInput(
      items: items,
      participants: participants,
      subtotal: subtotal,
      adjustments: adjustments,
      total: total,
      currency: displayCurrency,
      adjustmentMethod: adjustmentSplitMethod)
  }

  var purchaseDate: Date {
    get { ReceiptLocalDate.date(from: date) ?? .now }
    set { date = ReceiptLocalDate.string(from: newValue) }
  }

  /// What the items' line totals add up to.
  var itemsTotal: Money {
    items.reduce(.zero) { $0 + $1.lineTotal }
  }

  /// The tax a receipt that doesn't show any most likely charged: what its total has beyond a
  /// printed subtotal that matches the items. `nil` when the subtotal doesn't back that up, since
  /// the difference could then be an item that wasn't read.
  var impliedTax: Money? {
    let balance = balance
    guard balance.printedSubtotal != nil, balance.subtotalDifferenceUnits == 0,
      balance.totalDifferenceUnits > 0
    else { return nil }
    return balance.totalDifference
  }

  /// What the tip is a percentage of: the subtotal, with the tax and savings listed above it.
  /// Savings already in the subtotal are in it wherever they're listed.
  var tipBaseAmount: Money {
    tipBaseAmount(for: tipPercentage)
  }

  /// What a tip of `percentage` is worked out on, or what the tip is a percentage of when it's
  /// `nil`.
  func tipBaseAmount(for percentage: Int?) -> Money {
    tipBaseAmount(at: tipPlacement(for: percentage))
  }

  /// Whether the tip is worked out after tax.
  var isTipAfterTax: Bool {
    adjustments(above: .tip, in: adjustmentOrder).contains(.tax)
  }

  /// Whether the tip is worked out after savings, or `nil` when the receipt has none.
  var isTipAfterSavings: Bool? {
    isTipAfterSavings(at: tipPlacement(for: tipPercentage))
  }

  /// The suggested tips, as percentages of `tipBaseAmount`, along with the one the tip was chosen
  /// as if it's no longer suggested.
  var tipPresets: [AdjustmentPreset] {
    var percentages = TipSettings.percentages()
    if let tipPercentage, !percentages.contains(tipPercentage) {
      percentages = (percentages + [tipPercentage]).sorted()
    }
    return percentages.map { percentage in
      AdjustmentPreset.percentage(
        percentage, of: tipBaseAmount(for: percentage), currencyCode: displayCurrency)
    }
  }

  /// The suggested percentage the tip comes to, or `nil` when it's none or more than one of them.
  var suggestedTipPercentage: Int? {
    let units = ReceiptCurrency.minorUnits(tip, code: displayCurrency)
    let matches = tipPresets.filter {
      ReceiptCurrency.minorUnits($0.amount, code: displayCurrency) == units
    }
    return matches.count == 1 ? matches[0].percentage : nil
  }

  /// The line under a tip of `amount` that says what it's a percentage of, for a tip chosen as
  /// `percentage` or entered when it's `nil`.
  func tipCaption(for amount: Money, percentage: Int?) -> String? {
    let placement = tipPlacement(for: percentage)
    return TipBaseCaption.text(
      tip: amount, base: tipBaseAmount(at: placement),
      isAfterTax: isTipAfterTax, isAfterSavings: isTipAfterSavings(at: placement),
      currencyCode: displayCurrency)
  }

  /// Lists the adjustments in `order`. A tip chosen as a percentage becomes that percentage of
  /// its new base; any other tip keeps its amount.
  func setAdjustmentOrder(_ order: [ReceiptTotalAdjustment]) {
    guard order != adjustmentOrder, ReceiptTotalAdjustment.validOrder(order) != nil else { return }
    keepingBalance { adjustmentOrder = order }
  }

  /// Where savings are read to work out a tip of `percentage`, or an entered tip when it's `nil`.
  /// A tip that follows its base is worked out where the receipt is best explained with the tip
  /// each placement would give, so the tip can't move the base it's a percentage of. A receipt
  /// that adds up works any other percentage out where its tip is now, since its total will
  /// follow the tip.
  private func tipPlacement(for percentage: Int?) -> ReceiptBalance.SavingsPlacement {
    guard let percentage else { return balance.placement }
    if percentage != tipPercentage, balance.totalDifferenceUnits == 0 {
      return tipPlacement(for: tipPercentage)
    }
    return tipPlacement(for: percentage) {
      ReceiptBalance(splitInput) { placement in
        var input = splitInput
        input.adjustments[.tip] = tipAmount(percentage, at: placement)
        return input
      }.placement
    }
  }

  private func tipAmount(_ percentage: Int, at placement: ReceiptBalance.SavingsPlacement) -> Money
  {
    AdjustmentPreset.percentage(
      percentage, of: tipBaseAmount(at: placement), currencyCode: displayCurrency
    ).amount
  }

  private func tipBaseAmount(at placement: ReceiptBalance.SavingsPlacement) -> Money {
    let balance = balance
    let above = adjustments(above: .tip, in: adjustmentOrder)
    let tax = above.contains(.tax) ? tax : 0
    let savings =
      above.contains(.savings) && balance.subtractsSavingsFromSubtotal(at: placement) ? savings : 0
    return rounded(balance.subtotal + tax - savings)
  }

  private func isTipAfterSavings(at placement: ReceiptBalance.SavingsPlacement) -> Bool? {
    guard savings > 0 else { return nil }
    return adjustments(above: .tip, in: adjustmentOrder).contains(.savings)
      || !balance.subtractsSavingsFromSubtotal(at: placement)
  }

  private func adjustments(
    above adjustment: ReceiptTotalAdjustment,
    in order: [ReceiptTotalAdjustment]
  ) -> Set<ReceiptTotalAdjustment> {
    Set(order.prefix { $0 != adjustment })
  }

  /// Sets a tip chosen as a percentage to that percentage of its base, reading savings at
  /// `placement`, or where `tipPlacement(for:)` reads them when it's `nil`.
  func followTipBase(at placement: ReceiptBalance.SavingsPlacement? = nil) {
    guard let tipPercentage else { return }
    let amount = tipAmount(tipPercentage, at: placement ?? tipPlacement(for: tipPercentage))
    if adjustments[.tip] != amount { adjustments[.tip] = amount }
  }

  /// The savings as a percentage of the subtotal, at most all of it.
  var savingsPercentage: Double {
    get {
      let subtotal = balance.subtotal
      guard subtotal > 0 else { return 0 }
      return (savings * 100).fraction(of: subtotal)
    }
    set {
      savings = rounded(balance.subtotal * min(max(newValue, 0), 100) / 100)
    }
  }

  /// Makes `change`, keeping a total that added up adding up: a receipt whose amounts were right
  /// has its total follow a new tax, tip, savings, or subtotal. A total that didn't add up is left
  /// as printed, since the change may be what fixes it. A change typed into `field` is judged by
  /// how the receipt balanced when typing began, and a tip chosen as a percentage follows its base.
  func keepingBalance(_ field: ReceiptAmountField? = nil, _ change: () -> Void) {
    let typing = amountEditing.flatMap { $0.field == field ? $0 : nil }
    defer { amountEditing = typing }
    let before = typing?.balance ?? balance
    let tipPlacement = tipPlacement(for: tipPercentage)
    change()
    let follows = before.totalDifferenceUnits == 0
    followTipBase(at: follows ? tipPlacement : nil)
    guard follows else { return }
    let after = ReceiptBalance(splitInput, placement: before.placement)
    if after.totalDifferenceUnits != 0 {
      total = after.calculatedTotal
    }
  }

  /// Sets the printed subtotal, which a total that added up follows.
  func setSubtotal(_ amount: Money) {
    keepingBalance(.subtotal) { subtotal = amount }
  }

  /// Adds `adjustment` at `amount`, or sets it to `amount` when the receipt has it. A tip is entered
  /// as an amount.
  func addAdjustment(_ adjustment: ReceiptTotalAdjustment, amount: Money = 0) {
    if adjustment == .tip { setTipPercentage(nil) }
    keepingBalance {
      adjustments.add(adjustment)
      adjustments[adjustment] = amount
    }
  }

  func removeAdjustment(_ adjustment: ReceiptTotalAdjustment) {
    keepingBalance { adjustments.remove(adjustment) }
  }

  func addItem(lineTotal: Money = 0) -> ReceiptDraftItem.ID {
    let item = ReceiptDraftItem(
      item: ReceiptItem(description: "", quantity: 1, lineTotal: lineTotal))
    items.append(item)
    return item.id
  }

  func removeItem(id: ReceiptDraftItem.ID) {
    items.removeAll { $0.id == id }
  }

  /// Replaces an item with `count` items named "Name (n/count)" whose line totals sum to the
  /// original, with any leftover units of the currency assigned to the first items.
  @discardableResult
  func splitItem(id: ReceiptDraftItem.ID, into count: Int) -> [ReceiptDraftItem.ID] {
    guard count > 1, let index = items.firstIndex(where: { $0.id == id }) else { return [] }
    let item = items[index]
    let currency = displayCurrency
    let totalUnits = ReceiptCurrency.minorUnits(item.lineTotal, code: currency)
    let baseUnits = totalUnits / count
    let remainderUnits = totalUnits - baseUnits * count
    let name = item.description.trimmed
    let splitItems = (0..<count).map { offset in
      let extraUnits = offset < abs(remainderUnits) ? remainderUnits.signum() : 0
      return ReceiptDraftItem(
        id: UUID(),
        description: "\(name) (\(offset + 1)/\(count))",
        quantity: item.quantity / Double(count),
        lineTotal: ReceiptCurrency.amount(minorUnits: baseUnits + extraUnits, code: currency),
        participantIDs: item.participantIDs)
    }
    items.replaceSubrange(index...index, with: splitItems)
    return splitItems.map(\.id)
  }

  /// `amount` rounded to the smallest unit of the receipt's currency.
  private func rounded(_ amount: Money) -> Money {
    ReceiptCurrency.rounded(amount, code: displayCurrency)
  }
}
