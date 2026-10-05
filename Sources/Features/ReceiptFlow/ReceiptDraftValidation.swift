import Foundation

extension ReceiptDraft {
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
