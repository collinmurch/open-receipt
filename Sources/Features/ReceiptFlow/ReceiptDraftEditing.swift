import Foundation

extension ReceiptDraft {
  var normalizedCurrency: String {
    currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
  }

  var purchaseDate: Date {
    get { Self.parseDate(date) ?? .now }
    set { date = Self.formatDate(newValue) }
  }

  var validationIssues: [ReceiptEditorValidationIssue] {
    var issues: [ReceiptEditorValidationIssue] = []
    if !Self.isCurrencyCode(normalizedCurrency) {
      issues.append(.invalidCurrency)
    }
    for item in items {
      if item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.missingItemDescription(item.id))
      }
      if !item.quantity.isFinite || item.quantity <= 0 {
        issues.append(.invalidItemQuantity(item.id))
      }
      if !item.lineTotal.isFinite {
        issues.append(.invalidItemTotal(item.id))
      }
    }
    if !adjustments.isEmpty, !subtotal.isFinite { issues.append(.invalidSubtotal) }
    if adjustments.contains(.tax), !tax.isFinite { issues.append(.invalidTax) }
    if adjustments.contains(.tip), !tip.isFinite { issues.append(.invalidTip) }
    if adjustments.contains(.savings), !savings.isFinite { issues.append(.invalidSavings) }
    if !total.isFinite { issues.append(.invalidTotal) }
    return issues
  }

  var missingAdjustments: [ReceiptTotalAdjustment] {
    adjustments.missing
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

  func removeItems(at offsets: IndexSet) {
    for index in offsets.sorted(by: >) {
      items.remove(at: index)
    }
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

  func addAdjustment(_ adjustment: ReceiptTotalAdjustment) {
    adjustments.add(adjustment)
  }

  func removeAdjustment(_ adjustment: ReceiptTotalAdjustment) {
    adjustments.remove(adjustment)
  }

  private static func isCurrencyCode(_ value: String) -> Bool {
    value.count == 3 && value.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
  }

  private static func parseDate(_ value: String) -> Date? {
    let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-")
    guard parts.count == 3,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else { return nil }
    return receiptCalendar.date(from: DateComponents(year: year, month: month, day: day))
  }

  private static func formatDate(_ value: Date) -> String {
    let components = receiptCalendar.dateComponents([.year, .month, .day], from: value)
    guard let year = components.year, let month = components.month, let day = components.day else {
      return ""
    }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  private static let receiptCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
  }()
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
