import SwiftUI

struct ReceiptParsingClient: Sendable {
  typealias PreviewHandler = @Sendable (ReceiptParsePreview) async -> Void

  let usesSampleData: Bool
  /// Parses pages, reporting the receipt as it is read.
  let stream: @Sendable ([ReceiptPage], @escaping PreviewHandler) async throws -> ParsedReceipt
  /// Prepares the model ahead of a likely request, such as when the scanner opens.
  let prewarm: @Sendable () -> Void
  /// The model's availability and quota. Reading it in a view body tracks changes.
  let status: @MainActor @Sendable () -> ReceiptModelStatus
  let showLimitIncrease: @MainActor @Sendable () -> Void

  init(
    usesSampleData: Bool,
    stream:
      @escaping @Sendable ([ReceiptPage], @escaping PreviewHandler) async throws
      -> ParsedReceipt,
    prewarm: @escaping @Sendable () -> Void = {},
    status: @escaping @MainActor @Sendable () -> ReceiptModelStatus = { .available },
    showLimitIncrease: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    self.usesSampleData = usesSampleData
    self.prewarm = prewarm
    self.status = status
    self.showLimitIncrease = showLimitIncrease
    self.stream = stream
  }

  /// Creates a client that reports no progress while it parses.
  init(
    usesSampleData: Bool,
    parse: @escaping @Sendable ([ReceiptPage]) async throws -> ParsedReceipt
  ) {
    self.init(usesSampleData: usesSampleData, stream: { pages, _ in try await parse(pages) })
  }

  func parse(_ pages: [ReceiptPage]) async throws -> ParsedReceipt {
    try await stream(pages) { _ in }
  }

  #if DEBUG
    static let sample: ReceiptParsingClient = .sample(pacing: .milliseconds(280))

    /// Sample data that streams in the way a live response does, one row at a time.
    static func sample(pacing: Duration) -> ReceiptParsingClient {
      ReceiptParsingClient(
        usesSampleData: true,
        stream: { _, onPreview in
          let receipt = ReceiptParsingClient.sampleReceipt
          var preview = ReceiptParsePreview()
          try await Task.sleep(for: pacing * 3)
          preview.merchantName = receipt.merchantName
          preview.date = receipt.date
          await onPreview(preview)
          try await Task.sleep(for: pacing)
          preview.total = receipt.total
          preview.currency = receipt.currency
          await onPreview(preview)
          for item in receipt.items {
            let words = item.description.split(separator: " ")
            for count in 1...words.count {
              try await Task.sleep(for: pacing / 2)
              let description = words.prefix(count).joined(separator: " ")
              if count == 1 {
                preview.items.append(ReceiptParsePreview.Item(description: description))
              } else {
                preview.items[preview.items.count - 1].description = description
              }
              await onPreview(preview)
            }
            try await Task.sleep(for: pacing / 2)
            preview.items[preview.items.count - 1].quantity = item.quantity
            preview.items[preview.items.count - 1].lineTotal = item.lineTotal
            await onPreview(preview)
          }
          try await Task.sleep(for: pacing * 2)
          return receipt
        })
    }

    private static let sampleReceipt = ParsedReceipt(
      merchantName: "Juniper Market",
      date: "2026-08-10",
      subtotal: 29.50,
      tax: 2.44,
      tip: 5.00,
      total: 36.94,
      currency: "USD",
      payment: ReceiptPayment(method: "Card", last4: "4242"),
      items: [
        ReceiptItem(description: "Breakfast Sandwich", quantity: 2, lineTotal: 17.00),
        ReceiptItem(description: "Cold Brew", quantity: 1, lineTotal: 6.50),
        ReceiptItem(description: "Blueberry Muffin", quantity: 1, lineTotal: 6.00),
      ])
  #else
    static let live = ReceiptParsingClient(
      usesSampleData: false,
      stream: { pages, onPreview in
        try await ReceiptParser.parse(pages: pages, onPreview: onPreview)
      },
      prewarm: { ReceiptParser.prewarm() },
      status: { ReceiptParser.status() },
      showLimitIncrease: { ReceiptParser.showLimitIncrease() })
  #endif
}

extension ReceiptParsingClient {
  /// Sample data in Debug builds and the live parser in Release builds.
  static var standard: ReceiptParsingClient {
    #if DEBUG
      return .sample
    #else
      return .live
    #endif
  }
}

private struct ReceiptParsingClientKey: EnvironmentKey {
  static let defaultValue = ReceiptParsingClient.standard
}

extension EnvironmentValues {
  var receiptParsingClient: ReceiptParsingClient {
    get { self[ReceiptParsingClientKey.self] }
    set { self[ReceiptParsingClientKey.self] = newValue }
  }
}
