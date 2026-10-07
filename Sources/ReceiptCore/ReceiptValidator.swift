import Foundation

enum ReceiptValidator {
  private static let totalReconciliationWarning =
    "Subtotal, tax, tip, and savings do not reconcile with the final total."

  /// Whether `code` has the shape of an ISO 4217 code: three letters.
  static func isCurrencyCode(_ code: String) -> Bool {
    code.count == 3 && code.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
  }

  static func warnings(for receipt: ParsedReceipt) -> [String] {
    var warnings: [String] = []
    let amounts = [receipt.subtotal, receipt.tax, receipt.tip, receipt.savings, receipt.total]
    if amounts.contains(where: { !$0.isFinite }) {
      warnings.append("One or more receipt totals are not finite numbers.")
    }
    if amounts.contains(where: { $0 < 0 }) {
      warnings.append("One or more receipt totals are negative.")
    }
    if receipt.total == 0 {
      warnings.append("No nonzero final total was extracted.")
    }
    if !receipt.currency.isEmpty, !isCurrencyCode(receipt.currency) {
      warnings.append("Currency is not a three-letter ISO code.")
    }
    if receipt.items.contains(where: { $0.description.isEmpty }) {
      warnings.append("At least one item has no description.")
    }
    if receipt.items.contains(where: { !$0.quantity.isFinite || $0.quantity <= 0 }) {
      warnings.append("At least one item has an invalid quantity.")
    }
    if receipt.items.contains(where: { !$0.lineTotal.isFinite }) {
      warnings.append("At least one item has an invalid line total.")
    }
    if receipt.subtotal > 0 {
      if abs(reconciliationDifference(of: receipt)) > 0.03 {
        warnings.append(totalReconciliationWarning)
      }
    }
    return warnings
  }

  /// How far the total is from the other amounts. Some receipts apply savings before the
  /// subtotal and others print a subtotal before savings, so the closer reading wins.
  private static func reconciliationDifference(of receipt: ParsedReceipt) -> Double {
    let beforeSavings = receipt.subtotal + receipt.tax + receipt.tip
    let candidates = [beforeSavings, beforeSavings - receipt.savings]
    return candidates.map { receipt.total - $0 }.min { abs($0) < abs($1) } ?? receipt.total
  }
}
