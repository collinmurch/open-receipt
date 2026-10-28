/// A receipt as it is being read, built from a partially generated model response.
nonisolated struct ReceiptParsePreview: Sendable, Equatable {
  struct Item: Sendable, Equatable {
    var description: String
    var quantity: Double?
    var lineTotal: Money?
  }

  var merchantName: String?
  var date: String?
  var total: Money?
  var currency: String?
  var items: [Item] = []

  /// The sum of the line totals read so far.
  var itemTotal: Money {
    items.reduce(.zero) { $0 + ($1.lineTotal ?? .zero) }
  }
}
