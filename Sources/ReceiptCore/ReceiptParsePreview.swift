import Foundation

/// A receipt as it is being read, built from a partially generated model response.
public struct ReceiptParsePreview: Sendable, Equatable {
  public struct Item: Sendable, Equatable {
    public var description: String
    public var quantity: Double?
    public var lineTotal: Double?

    public init(description: String, quantity: Double? = nil, lineTotal: Double? = nil) {
      self.description = description
      self.quantity = quantity
      self.lineTotal = lineTotal
    }
  }

  public var merchantName: String?
  public var date: String?
  public var total: Double?
  public var currency: String?
  public var items: [Item]

  public init(
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
  public var itemTotal: Double {
    items.reduce(0) { $0 + ($1.lineTotal ?? 0) }
  }
}
