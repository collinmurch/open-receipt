import Foundation

/// A receipt as it is being read, built from a partially generated model response.
struct ReceiptParsePreview: Sendable, Equatable {
  struct Item: Sendable, Equatable {
    var description: String
    var quantity: Double?
    var lineTotal: Double?

    init(description: String, quantity: Double? = nil, lineTotal: Double? = nil) {
      self.description = description
      self.quantity = quantity
      self.lineTotal = lineTotal
    }
  }

  var merchantName: String?
  var date: String?
  var total: Double?
  var currency: String?
  var items: [Item]

  init(
    merchantName: String? = nil,
    date: String? = nil,
    total: Double? = nil,
    currency: String? = nil,
    items: [Item] = []
  ) {
    self.merchantName = merchantName
    self.date = date
    self.total = total
    self.currency = currency
    self.items = items
  }

  /// The sum of the line totals read so far.
  var itemTotal: Double {
    items.reduce(0) { $0 + ($1.lineTotal ?? 0) }
  }
}
