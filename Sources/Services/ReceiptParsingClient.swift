import SwiftUI

struct ReceiptParsingClient: Sendable {
  typealias PreviewHandler = @Sendable (ReceiptParsePreview) async -> Void

  private let isSampleData: @Sendable () -> Bool
  /// Parses pages, reporting the receipt as it is read.
  let stream: @Sendable ([ReceiptPage], @escaping PreviewHandler) async throws -> ParsedReceipt
  /// Prepares the model ahead of a likely request, such as when the scanner opens.
  let prewarm: @Sendable () -> Void
  /// The model's availability and quota. Reading it in a view body tracks changes.
  let status: @MainActor @Sendable () -> ReceiptModelStatus
  let showLimitIncrease: @MainActor @Sendable () -> Void

  init(
    usesSampleData: @autoclosure @escaping @Sendable () -> Bool,
    stream:
      @escaping @Sendable ([ReceiptPage], @escaping PreviewHandler) async throws
      -> ParsedReceipt,
    prewarm: @escaping @Sendable () -> Void = {},
    status: @escaping @MainActor @Sendable () -> ReceiptModelStatus = { .available },
    showLimitIncrease: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    isSampleData = usesSampleData
    self.prewarm = prewarm
    self.status = status
    self.showLimitIncrease = showLimitIncrease
    self.stream = stream
  }

  /// Creates a client that reports no progress while it parses.
  init(
    usesSampleData: @autoclosure @escaping @Sendable () -> Bool,
    parse: @escaping @Sendable ([ReceiptPage]) async throws -> ParsedReceipt
  ) {
    self.init(usesSampleData: usesSampleData(), stream: { pages, _ in try await parse(pages) })
  }

  /// Whether reads return the sample receipt instead of reading the pages.
  var usesSampleData: Bool {
    isSampleData()
  }

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

  #if targetEnvironment(simulator)
    /// The simulator can't reach Private Cloud Compute, so only sample receipts can be read.
    static let live = ReceiptParsingClient(
      usesSampleData: false,
      stream: { _, _ in
        throw ReceiptParserError.modelUnavailable(ReceiptParsingClient.simulatorReason)
      },
      status: { .unavailable(ReceiptParsingClient.simulatorReason) })

    private static let simulatorReason =
      "Private Cloud Compute isn’t available in Simulator. Turn on Sample Receipts in Settings."
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

  /// The live parser, or the sample while a testing build has sample receipts on. The setting is
  /// checked on every call, so switching it applies to the next read.
  static let standard = ReceiptParsingClient(
    usesSampleData: SampleReceipts.isEnabled,
    stream: { pages, onPreview in
      let client = SampleReceipts.isEnabled ? ReceiptParsingClient.sample : .live
      return try await client.stream(pages, onPreview)
    },
    prewarm: {
      if !SampleReceipts.isEnabled { ReceiptParsingClient.live.prewarm() }
    },
    status: { SampleReceipts.isEnabled ? .available : ReceiptParsingClient.live.status() },
    showLimitIncrease: { ReceiptParsingClient.live.showLimitIncrease() })
}

extension EnvironmentValues {
  @Entry var receiptParsingClient = ReceiptParsingClient.standard
}
