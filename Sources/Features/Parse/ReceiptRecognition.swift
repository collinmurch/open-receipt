import CoreGraphics
import Foundation
import Observation

/// One receipt being read by the model. It outlives the screen that started it, so a person can
/// leave while the receipt is read and find the result in their library.
@MainActor
@Observable
final class ReceiptRecognition: Identifiable {
  enum Status: Equatable {
    case reading
    case waitingForConnection
    case saving
    case finished
  }

  enum Outcome {
    case recognized(ReceiptDocument)
    case failed(message: String, isRetryable: Bool)
  }

  /// The receipt identifier, which is also the scan identifier.
  let id: UUID
  let backgroundStyle: ReceiptBackgroundStyle
  let capturedAt: Date
  let pageCount: Int
  private(set) var preview = ReceiptParsePreview()
  private(set) var status = Status.reading
  private(set) var thumbnail: CGImage?

  @ObservationIgnored let scan: ReceiptScan
  /// The stored receipt, once it exists. A rescan starts with it.
  @ObservationIgnored var document: ReceiptDocument?
  /// The parsed receipt, kept so a retry after a failed save never reads the receipt again.
  @ObservationIgnored var parsedReceipt: ParsedReceipt?
  @ObservationIgnored var task: Task<Outcome, Never>?

  init(
    scan: ReceiptScan,
    backgroundStyle: ReceiptBackgroundStyle,
    document: ReceiptDocument? = nil,
    parsedReceipt: ParsedReceipt? = nil
  ) {
    id = scan.id
    self.scan = scan
    self.backgroundStyle = backgroundStyle
    self.document = document
    self.parsedReceipt = parsedReceipt
    capturedAt = scan.capturedAt
    pageCount = scan.pages.count
  }

  /// Whether this recognition replaces the values of a receipt that was already read.
  var isRescan: Bool {
    document?.recognition.status == .succeeded
  }

  var outcome: Outcome {
    get async {
      await task?.value ?? .failed(message: "The receipt was not read.", isRetryable: true)
    }
  }

  func update(_ preview: ReceiptParsePreview) {
    guard preview != self.preview else { return }
    self.preview = preview
  }

  func update(_ status: Status) {
    guard status != self.status else { return }
    self.status = status
  }

  func update(thumbnail: CGImage?) {
    self.thumbnail = thumbnail
  }

  func resetPreview() {
    update(ReceiptParsePreview())
  }
}
