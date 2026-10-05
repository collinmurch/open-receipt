import Foundation

struct ExpectedReceipt: Codable {
  var currency: String?
  var subtotal: Double?
  var tax: Double?
  var tip: Double?
  var savings: Double?
  var total: Double?
  var itemCount: Int?
  var amountTolerance: Double?
  var items: [ExpectedItem]?
}

struct ExpectedItem: Codable {
  var rawName: String
  var lineTotal: Double
  var quantity: Double?
  var unitPrice: Double?
}
