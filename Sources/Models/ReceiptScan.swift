import Foundation

struct ReceiptScan: Identifiable, Sendable {
  enum Source: String, Codable, Sendable {
    case documentCamera
    case photoLibrary
    case manual
  }

  let id: UUID
  let pages: [ReceiptPage]
  let capturedAt: Date
  let source: Source

  init(
    id: UUID = UUID(),
    pages: [ReceiptPage],
    capturedAt: Date = Date(),
    source: Source = .documentCamera
  ) {
    self.id = id
    self.pages = pages
    self.capturedAt = capturedAt
    self.source = source
  }
}

extension ReceiptScan {
  /// The scan stored with `document`, with its `pages` loaded.
  init(document: ReceiptDocument, pages: [ReceiptPage]) {
    self.init(
      id: document.id, pages: pages, capturedAt: document.scan.capturedAt,
      source: document.scan.source)
  }
}
