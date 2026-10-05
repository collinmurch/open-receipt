import Foundation

extension ReceiptDraft {
  var normalizedCurrency: String {
    currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
  }

  /// The currency code amounts are formatted with while the entered code may be incomplete.
  var displayCurrency: String {
    ReceiptCurrency.displayCode(normalizedCurrency)
  }

  var purchaseDate: Date {
    get { ReceiptLocalDate.date(from: date) ?? .now }
    set { date = ReceiptLocalDate.string(from: newValue) }
  }

  var expectedSubtotal: Double {
    items.reduce(0) { $0 + $1.lineTotal }
  }

  var expectedTotal: Double {
    expectedSubtotal + tax + tip - savings
  }

  var subtotalNeedsCorrection: Bool {
    (subtotal - expectedSubtotal).isNonzeroInCents
  }

  var totalNeedsCorrection: Bool {
    (total - expectedTotal).isNonzeroInCents
  }

  var savingsPercentage: Double {
    get {
      guard expectedSubtotal > 0 else { return 0 }
      return savings / expectedSubtotal * 100
    }
    set {
      savings = max(0, expectedSubtotal * newValue / 100)
    }
  }

  var tipPercentage: Double {
    get {
      guard expectedSubtotal > 0 else { return 0 }
      return tip / expectedSubtotal * 100
    }
    set {
      tip = max(0, expectedSubtotal * newValue / 100)
    }
  }

  func addItem() -> ReceiptDraftItem.ID {
    let item = ReceiptDraftItem(
      item: ReceiptItem(description: "", quantity: 1, lineTotal: 0))
    items.append(item)
    return item.id
  }

  func removeItem(id: ReceiptDraftItem.ID) {
    items.removeAll { $0.id == id }
  }

  /// Replaces an item with `count` items named "Name (n/count)" whose line totals sum to the
  /// original, with any leftover cents assigned to the first items.
  @discardableResult
  func splitItem(id: ReceiptDraftItem.ID, into count: Int) -> [ReceiptDraftItem.ID] {
    guard count > 1, let index = items.firstIndex(where: { $0.id == id }) else { return [] }
    let item = items[index]
    let totalCents = Int((item.lineTotal * 100).rounded())
    let baseCents = totalCents / count
    let remainderCents = totalCents - baseCents * count
    let name = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
    let splitItems = (0..<count).map { offset in
      let extraCents = offset < abs(remainderCents) ? remainderCents.signum() : 0
      return ReceiptDraftItem(
        id: UUID(),
        description: "\(name) (\(offset + 1)/\(count))",
        quantity: item.quantity / Double(count),
        lineTotal: Double(baseCents + extraCents) / 100,
        participantIDs: item.participantIDs)
    }
    items.replaceSubrange(index...index, with: splitItems)
    return splitItems.map(\.id)
  }

  func fixTotal() {
    total = expectedTotal
  }

  /// The amount `adjustment` adds to the total, negative for savings.
  func signedAmount(of adjustment: ReceiptTotalAdjustment) -> Double {
    let amount = adjustments[adjustment] ?? 0
    return amount == 0 ? 0 : amount * adjustment.sign
  }
}
