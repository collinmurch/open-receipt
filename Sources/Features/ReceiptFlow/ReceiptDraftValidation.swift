import Foundation

/// One of a receipt's amounts outside its items.
nonisolated enum ReceiptAmountField: Hashable {
  case subtotal
  case adjustment(ReceiptTotalAdjustment)
  case total
}

/// The row a receipt issue is shown beside.
nonisolated enum ReceiptIssueLocation: Hashable {
  case currency
  case item(ReceiptDraftItem.ID)
  case amount(ReceiptAmountField)
}

/// Something on a receipt that needs fixing, shown beside the row it's about.
nonisolated enum ReceiptIssue: Identifiable, Hashable {
  case invalidCurrency
  case missingItemDescription(ReceiptDraftItem.ID)
  case invalidItemQuantity(ReceiptDraftItem.ID)
  case negativeAmount(ReceiptAmountField)
  case zeroTotal

  var id: Self { self }

  var location: ReceiptIssueLocation {
    switch self {
    case .invalidCurrency: .currency
    case .missingItemDescription(let id), .invalidItemQuantity(let id): .item(id)
    case .negativeAmount(let field): .amount(field)
    case .zeroTotal: .amount(.total)
    }
  }

  var message: String {
    switch self {
    case .invalidCurrency: "Choose a currency."
    case .missingItemDescription: "Enter an item name."
    case .invalidItemQuantity: "Quantity must be greater than zero."
    case .negativeAmount(let field): "The \(field.name) can’t be negative."
    case .zeroTotal: "Enter the receipt’s total."
    }
  }
}

nonisolated extension ReceiptAmountField {
  fileprivate var name: String {
    switch self {
    case .subtotal: "subtotal"
    case .adjustment(.tax): "tax amount"
    case .adjustment(.tip): "tip amount"
    case .adjustment(.savings): "savings amount"
    case .total: "total"
    }
  }
}

extension ReceiptDraft {
  /// The issues shown beside one row.
  func issues(at location: ReceiptIssueLocation) -> [ReceiptIssue] {
    issues.filter { $0.location == location }
  }

  func uncachedIssues() -> [ReceiptIssue] {
    var issues: [ReceiptIssue] = []
    if !ReceiptValidator.isCurrencyCode(normalizedCurrency) {
      issues.append(.invalidCurrency)
    }
    issues += items.flatMap(\.issues)
    issues += amountIssues(subtotal, at: .subtotal)
    for adjustment in ReceiptTotalAdjustment.allCases {
      if let amount = adjustments[adjustment] {
        issues += amountIssues(amount, at: .adjustment(adjustment))
      }
    }
    issues += amountIssues(total, at: .total)
    if total == 0 { issues.append(.zeroTotal) }
    return issues
  }

  private func amountIssues(_ amount: Money, at field: ReceiptAmountField) -> [ReceiptIssue] {
    amount < 0 ? [.negativeAmount(field)] : []
  }
}

nonisolated extension ReceiptDraftItem {
  var issues: [ReceiptIssue] {
    var issues: [ReceiptIssue] = []
    if description.trimmed.isEmpty {
      issues.append(.missingItemDescription(id))
    }
    if !quantity.isFinite || quantity <= 0 {
      issues.append(.invalidItemQuantity(id))
    }
    return issues
  }
}
