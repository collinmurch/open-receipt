public nonisolated struct ReceiptItem: Sendable, Equatable {
  public let description: String
  public let quantity: Double
  public let lineTotal: Money

  public init(
    description: String,
    quantity: Double,
    lineTotal: Money
  ) {
    self.description = description
    self.quantity = quantity
    self.lineTotal = lineTotal
  }
}

public nonisolated struct ReceiptPayment: Sendable, Equatable {
  public let method: String?
  public let last4: String?
  public let authCode: String?

  public init(method: String? = nil, last4: String? = nil, authCode: String? = nil) {
    self.method = method
    self.last4 = last4
    self.authCode = authCode
  }
}

public nonisolated struct ParsedReceipt: Sendable {
  public var merchantName: String
  public var date: String
  public var subtotal: Money
  public var tax: Money
  public var tip: Money
  public var savings: Money
  public var total: Money
  public var currency: String
  public var payment: ReceiptPayment?
  public var items: [ReceiptItem]
  public var warnings: [String]

  public init(
    merchantName: String = "",
    date: String = "",
    subtotal: Money = 0,
    tax: Money = 0,
    tip: Money = 0,
    savings: Money = 0,
    total: Money = 0,
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
