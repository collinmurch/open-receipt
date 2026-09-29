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

  var validationIssues: [ReceiptEditorValidationIssue] {
    var issues: [ReceiptEditorValidationIssue] = []
    if !ReceiptValidator.isCurrencyCode(normalizedCurrency) {
      issues.append(.invalidCurrency)
    }
    issues += items.flatMap(\.validationIssues)
    if !adjustments.isEmpty, !subtotal.isFinite { issues.append(.invalidSubtotal) }
    if adjustments.contains(.tax), !tax.isFinite { issues.append(.invalidTax) }
    if adjustments.contains(.tip), !tip.isFinite { issues.append(.invalidTip) }
    if adjustments.contains(.savings), !savings.isFinite { issues.append(.invalidSavings) }
    if !total.isFinite { issues.append(.invalidTotal) }
    return issues
  }

  var expectedSubtotal: Double {
    items.reduce(0) { $0 + $1.lineTotal }
  }

  var expectedTotal: Double {
    expectedSubtotal + tax + tip - savings
  }

  var subtotalNeedsCorrection: Bool {
    abs(subtotal - expectedSubtotal) >= 0.005
  }

  var totalNeedsCorrection: Bool {
    abs(total - expectedTotal) >= 0.005
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

  @discardableResult
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

extension ReceiptDraftItem {
  var validationIssues: [ReceiptEditorValidationIssue] {
    var issues: [ReceiptEditorValidationIssue] = []
    if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.missingItemDescription(id))
    }
    if !quantity.isFinite || quantity <= 0 {
      issues.append(.invalidItemQuantity(id))
    }
    if !lineTotal.isFinite {
      issues.append(.invalidItemTotal(id))
    }
    return issues
  }
}

enum ReceiptEditorValidationIssue: Identifiable, Equatable {
  case invalidCurrency
  case missingItemDescription(ReceiptDraftItem.ID)
  case invalidItemQuantity(ReceiptDraftItem.ID)
  case invalidItemTotal(ReceiptDraftItem.ID)
  case invalidSubtotal
  case invalidTax
  case invalidTip
  case invalidSavings
  case invalidTotal

  var id: String {
    switch self {
    case .invalidCurrency: "currency"
    case .missingItemDescription(let id): "item-\(id)-description"
    case .invalidItemQuantity(let id): "item-\(id)-quantity"
    case .invalidItemTotal(let id): "item-\(id)-total"
    case .invalidSubtotal: "subtotal"
    case .invalidTax: "tax"
    case .invalidTip: "tip"
    case .invalidSavings: "savings"
    case .invalidTotal: "total"
    }
  }

  var message: String {
    switch self {
    case .invalidCurrency:
      "Enter a three-letter currency code."
    case .missingItemDescription:
      "Enter a name for each item."
    case .invalidItemQuantity:
      "Each item quantity must be greater than zero."
    case .invalidItemTotal:
      "Enter a valid total for each item."
    case .invalidSubtotal:
      "Enter a valid subtotal."
    case .invalidTax:
      "Enter a valid tax amount."
    case .invalidTip:
      "Enter a valid tip amount."
    case .invalidSavings:
      "Enter a valid savings amount."
    case .invalidTotal:
      "Enter a valid receipt total."
    }
  }
}
