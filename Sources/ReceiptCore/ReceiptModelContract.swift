import Foundation
import FoundationModels

public enum ReceiptModelContract {
  public static let version = 1

  public static let instructions = """
    Read one purchase receipt from the supplied images. The images may show overlapping parts of the receipt in any order. Use only visible print.
    When overlapping images show the same printed row, return it once. Rows with identical text at different places on the receipt are separate charges.
    Return each nonzero purchase charge from the item section exactly once, in printed order. The item section ends when the receipt summary begins.
    A product row and its following quantity, weight, unit-price, or tare lines describe one purchase. Use those detail lines to set the product quantity and line total. Do not return them as separate items.
    A nonzero charge printed before the subtotal is an item unless it is a product detail, discount, or savings row. This includes tax, fee, and deposit charges. Never move a tax-labeled row from before the subtotal into taxComponents.
    Do not return zero-value rows or discount and savings rows as items. Combine printed discounts and savings in the savings field.
    When a subtotal is printed, compare it with the sum of item line totals and account for printed savings exactly once. If they do not reconcile, recheck the item section for omitted or duplicated rows.
    TaxComponents contains only tax lines printed in the receipt summary after the subtotal. Transcribe each summary tax label and charged amount. Ignore percentage rates.
    """

  public static let prompt =
    "Parse the supplied images as one receipt into the requested structure."

  public static func imageLabel(at index: Int) -> String {
    "receipt-image-\(index + 1)"
  }

  public static func receipt(from data: Data) throws -> ParsedReceipt {
    receipt(from: try JSONDecoder().decode(Response.self, from: data))
  }

  static func receipt(from response: Response) -> ParsedReceipt {
    var receipt = ParsedReceipt(
      merchantName: response.merchantName.trimmingCharacters(in: .whitespacesAndNewlines),
      date: response.date.trimmingCharacters(in: .whitespacesAndNewlines),
      subtotal: response.subtotal,
      tax: response.taxComponents.reduce(0) { $0 + $1.amount },
      tip: response.tip,
      savings: abs(response.savings),
      total: response.total,
      currency: response.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
      payment: response.payment?.parsedPayment,
      items: response.items.map(\.parsedItem))
    receipt.warnings.append(contentsOf: ReceiptValidator.warnings(for: receipt))
    return receipt
  }

  static func preview(from partial: Response.PartiallyGenerated) -> ReceiptParsePreview {
    let currency = partial.currency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return ReceiptParsePreview(
      merchantName: partial.merchantName.flatMap(nonEmpty),
      date: partial.date.flatMap(nonEmpty),
      total: partial.total,
      currency: currency.flatMap { ReceiptValidator.isCurrencyCode($0) ? $0 : nil },
      items: (partial.items ?? []).compactMap { item in
        guard let description = item.description.flatMap(nonEmpty) else { return nil }
        return ReceiptParsePreview.Item(
          description: description,
          quantity: item.quantity,
          lineTotal: item.lineTotal)
      })
  }

  private static func nonEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  @Generable(description: "A faithful structured representation of one purchase receipt")
  struct Response: Codable {
    @Guide(description: "Merchant name exactly as printed, or an empty string")
    let merchantName: String
    @Guide(description: "Purchase date as YYYY-MM-DD, or an empty string")
    let date: String
    @Guide(description: "Printed subtotal before tax, or zero when absent")
    let subtotal: Double
    @Guide(description: "Printed tip or gratuity, or zero when absent")
    let tip: Double
    @Guide(description: "Printed receipt-level savings, or zero when absent")
    let savings: Double
    @Guide(description: "Final printed amount paid or due")
    let total: Double
    @Guide(description: "Three-letter ISO 4217 currency code")
    let currency: String
    @Guide(description: "Payment details when explicitly printed")
    let payment: Payment?
    @Guide(description: "Tax lines from the receipt summary")
    let taxComponents: [TaxComponent]
    @Guide(description: "Nonzero charged rows from the item section")
    let items: [Item]
  }

  @Generable(description: "One tax line from the receipt summary")
  struct TaxComponent: Codable {
    let label: String
    @Guide(description: "Charged amount, not the percentage rate")
    let amount: Double
  }

  @Generable(description: "One nonzero charged row from the item section")
  struct Item: Codable {
    let description: String
    @Guide(description: "Printed quantity, or one when absent")
    let quantity: Double
    @Guide(description: "Printed total for this purchase row")
    let lineTotal: Double

    var parsedItem: ReceiptItem {
      ReceiptItem(
        description: description.trimmingCharacters(in: .whitespacesAndNewlines),
        quantity: quantity,
        lineTotal: lineTotal)
    }
  }

  @Generable(description: "Payment details explicitly printed on the receipt")
  struct Payment: Codable {
    @Guide(description: "Printed payment method, or an empty string")
    let method: String
    @Guide(description: "Printed final four card digits, or an empty string")
    let last4: String
    @Guide(description: "Printed authorization code, or an empty string")
    let authCode: String

    var parsedPayment: ReceiptPayment? {
      let method = nonEmpty(method)
      let last4 = nonEmpty(last4)
      let authCode = nonEmpty(authCode)
      guard method != nil || last4 != nil || authCode != nil else { return nil }
      return ReceiptPayment(method: method, last4: last4, authCode: authCode)
    }
  }
}

public enum ReceiptValidator {
  public static let totalReconciliationWarning =
    "Subtotal, tax, tip, and savings do not reconcile with the final total."

  /// Whether `code` has the shape of an ISO 4217 code: three letters.
  public static func isCurrencyCode(_ code: String) -> Bool {
    code.count == 3 && code.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
  }

  public static func warnings(for receipt: ParsedReceipt) -> [String] {
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
      let difference = ReceiptTotalReconciler.difference(
        subtotal: receipt.subtotal,
        tax: receipt.tax,
        tip: receipt.tip,
        savings: receipt.savings,
        total: receipt.total)
      if abs(difference) > 0.03 {
        warnings.append(totalReconciliationWarning)
      }
    }
    return warnings
  }
}

enum ReceiptTotalReconciler {
  static func difference(
    subtotal: Double,
    tax: Double,
    tip: Double,
    savings: Double,
    total: Double
  ) -> Double {
    // Some receipts apply savings before subtotal; others print a pre-savings subtotal.
    let candidates = [subtotal + tax + tip, subtotal + tax + tip - savings]
    return candidates.map { total - $0 }.min { abs($0) < abs($1) } ?? total
  }
}
