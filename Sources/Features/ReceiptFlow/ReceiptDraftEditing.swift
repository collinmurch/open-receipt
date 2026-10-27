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
  var itemsTotal: Double {
    items.reduce(0) { $0 + $1.lineTotal }
  }

  var balance: ReceiptBalance {
    ReceiptBalance(splitInput)
  }

  /// The tax a receipt that doesn't show any most likely charged: what its total has beyond a
  /// printed subtotal that matches the items. `nil` when the subtotal doesn't back that up, since
  /// the difference could then be an item that wasn't read.
  var impliedTax: Double? {
    let balance = balance
    guard balance.printedSubtotal != nil, balance.subtotalDifferenceUnits == 0,
      balance.totalDifferenceUnits > 0
    else { return nil }
    return balance.totalDifference
  }

  /// What the tip is a percentage of: the subtotal, with the tax and savings listed above it.
  /// Savings already in the subtotal are in it wherever they're listed.
  var tipBaseAmount: Double {
    tipBaseAmount(in: adjustmentOrder)
  }

  /// Whether the tip is worked out after tax.
  var isTipAfterTax: Bool {
    adjustments(above: .tip, in: adjustmentOrder).contains(.tax)
  }

  /// Whether the tip is worked out after savings, or `nil` when the receipt has none.
  var isTipAfterSavings: Bool? {
    guard savings > 0 else { return nil }
    return adjustments(above: .tip, in: adjustmentOrder).contains(.savings)
      || !balance.subtractsSavingsFromSubtotal
  }

  /// Lists the adjustments in `order`. A tip at one of `percentages` of its old base becomes that
  /// percentage of the new one; any other tip keeps its amount.
  func setAdjustmentOrder(
    _ order: [ReceiptTotalAdjustment],
    percentages: [Int] = TipSettings.percentages()
  ) {
    guard order != adjustmentOrder, ReceiptTotalAdjustment.validOrder(order) != nil else { return }
    let oldAmount = tipBaseAmount
    let newAmount = tipBaseAmount(in: order)
    let percentage = percentages.first {
      abs(
        AdjustmentPreset.percentage($0, of: oldAmount, currencyCode: displayCurrency).amount - tip)
        < CurrencyAmountInput.tolerance
    }
    adjustmentOrder = order
    if adjustments.contains(.tip), let percentage {
      tip =
        AdjustmentPreset.percentage(percentage, of: newAmount, currencyCode: displayCurrency).amount
    }
  }

  private func tipBaseAmount(in order: [ReceiptTotalAdjustment]) -> Double {
    let balance = balance
    let above = adjustments(above: .tip, in: order)
    let tax = above.contains(.tax) ? tax : 0
    let savings =
      above.contains(.savings) && balance.subtractsSavingsFromSubtotal ? savings : 0
    return rounded(balance.subtotal + tax - savings)
  }

  private func adjustments(
    above adjustment: ReceiptTotalAdjustment,
    in order: [ReceiptTotalAdjustment]
  ) -> Set<ReceiptTotalAdjustment> {
    Set(order.prefix { $0 != adjustment })
  }

  var savingsPercentage: Double {
    get {
      guard itemsTotal > 0 else { return 0 }
      return savings / itemsTotal * 100
    }
    set {
      savings = rounded(max(0, itemsTotal * newValue / 100))
    }
  }

  /// Makes `change`, keeping a total that added up adding up: a receipt whose amounts were right
  /// has its total follow a new tax, tip, savings, or subtotal. A total that didn't add up is left
  /// as printed, since the change may be what fixes it.
  func keepingBalance(_ change: () -> Void) {
    let before = balance
    change()
    guard before.totalDifferenceUnits == 0 else { return }
    let after = ReceiptBalance(splitInput, placement: before.placement)
    if after.totalDifferenceUnits != 0 {
      total = after.calculatedTotal
    }
  }

  /// Sets the printed subtotal, which a total that added up follows.
  func setSubtotal(_ amount: Double) {
    keepingBalance { subtotal = amount }
  }

  /// Sets the subtotal to what the items come to.
  func matchSubtotalToItems() {
    guard let calculated = balance.calculatedSubtotal else { return }
    setSubtotal(calculated)
  }

  /// Sets the total to what the subtotal and adjustments come to.
  func matchTotal() {
    total = balance.calculatedTotal
  }

  func addAdjustment(_ adjustment: ReceiptTotalAdjustment, amount: Double = 0) {
    keepingBalance {
      adjustments.add(adjustment)
      adjustments[adjustment] = amount
    }
  }

  func removeAdjustment(_ adjustment: ReceiptTotalAdjustment) {
    keepingBalance { adjustments.remove(adjustment) }
  }

  func addItem(lineTotal: Double = 0) -> ReceiptDraftItem.ID {
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
    let name = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
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
  private func rounded(_ amount: Double) -> Double {
    ReceiptCurrency.rounded(amount, code: displayCurrency)
  }
}
