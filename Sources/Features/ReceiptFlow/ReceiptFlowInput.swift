import Foundation

struct ReceiptFlowInput: Identifiable, Hashable {
  enum Source {
    case create
    case storedReceipt
    case recognition(ReceiptRecognition)
    /// A new scan to store without reading, because the model can't read it.
    case unreadScan(ReceiptScan)
  }

  /// The receipt identifier.
  let id: UUID
  let source: Source
  /// The receipt's colors, when they are known before it loads.
  let backgroundStyle: ReceiptBackgroundStyle?
  /// The stored receipt, when it was loaded before the screen opened, so the receipt shows on the
  /// first frame instead of loading during the transition.
  var preloadedDocument: ReceiptDocument?

  static func create(
    id: UUID = UUID(),
    backgroundStyle: ReceiptBackgroundStyle = .random()
  ) -> ReceiptFlowInput {
    ReceiptFlowInput(id: id, source: .create, backgroundStyle: backgroundStyle)
  }

  static func storedReceipt(
    _ id: UUID,
    backgroundStyle: ReceiptBackgroundStyle? = nil,
    document: ReceiptDocument? = nil
  ) -> ReceiptFlowInput {
    ReceiptFlowInput(
      id: id,
      source: .storedReceipt,
      backgroundStyle: backgroundStyle,
      preloadedDocument: document)
  }

  @MainActor
  static func recognition(_ recognition: ReceiptRecognition) -> ReceiptFlowInput {
    ReceiptFlowInput(
      id: recognition.id,
      source: .recognition(recognition),
      backgroundStyle: recognition.backgroundStyle)
  }

  /// Opens a new scan. It is read right away, or stored unread when the model is unavailable so
  /// its values can be entered by hand.
  @MainActor
  static func scan(
    _ scan: ReceiptScan,
    recognitions: ReceiptRecognitionCenter
  ) -> ReceiptFlowInput {
    guard case .unavailable = recognitions.modelStatus else {
      return .recognition(recognitions.recognize(scan))
    }
    return ReceiptFlowInput(id: scan.id, source: .unreadScan(scan), backgroundStyle: .random())
  }

  static func == (lhs: ReceiptFlowInput, rhs: ReceiptFlowInput) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}
