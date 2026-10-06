/// A receipt as it is being read, built from a partially generated model response.
struct ReceiptParsePreview: Sendable, Equatable {
  struct Item: Sendable, Equatable {
    var description: String
    var quantity: Double?
    var lineTotal: Double?
  }

  var merchantName: String?
  var date: String?
  var total: Double?
  var currency: String?
  var items: [Item] = []

  /// The sum of the line totals read so far.
  var itemTotal: Double {
    items.reduce(0) { $0 + ($1.lineTotal ?? 0) }
  }
}
