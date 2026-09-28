import Foundation

public struct ReceiptItem: Sendable, Equatable {
  public let description: String
  public let quantity: Double
  public let lineTotal: Double

  public init(
    description: String,
    quantity: Double,
    lineTotal: Double
  ) {
    self.description = description
    self.quantity = quantity
    self.lineTotal = lineTotal
  }
}

public struct ReceiptPayment: Sendable, Equatable {
  public let method: String?
  public let last4: String?
  public let authCode: String?

  public init(method: String? = nil, last4: String? = nil, authCode: String? = nil) {
    self.method = method
    self.last4 = last4
    self.authCode = authCode
  }
}

public struct ParsedReceipt: Sendable {
  public var merchantName: String
  public var date: String
  public var subtotal: Double
  public var tax: Double
  public var tip: Double
  public var savings: Double
  public var total: Double
  public var currency: String
  public var payment: ReceiptPayment?
  public var items: [ReceiptItem]
  public var warnings: [String]

  public init(
    merchantName: String = "",
    date: String = "",
    subtotal: Double = 0,
    tax: Double = 0,
    tip: Double = 0,
    savings: Double = 0,
    total: Double = 0,
    currency: String = "USD",
    payment: ReceiptPayment? = nil,
    items: [ReceiptItem] = [],
    warnings: [String] = []
  ) {
    self.merchantName = merchantName
    self.date = date
    self.subtotal = subtotal
    self.tax = tax
    self.tip = tip
    self.savings = savings
    self.total = total
    self.currency = currency
    self.payment = payment
    self.items = items
    self.warnings = warnings
  }
}
