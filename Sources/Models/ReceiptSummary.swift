import Foundation

struct ReceiptSummary: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  let updatedAt: Date
  let capturedAt: Date
  let backgroundStyle: ReceiptBackgroundStyle
  let recognitionStatus: ReceiptDocument.Recognition.Status
  let merchantName: String?
  let localDate: String?
  let total: Double?
  let currency: String?
  let isUnavailable: Bool
  let unavailableDescription: String?
  /// When an unread receipt is read again on its own after the reading limit resets.
  var deferredUntil: Date?
  /// The saved people on the receipt.
  var personIDs: Set<UUID> = []
  /// Whether anyone besides the owner was added without a saved person, and so may be one.
  var hasUnlinkedPeople = false

  /// The merchant's name, or "Receipt" when the receipt doesn't name one.
  var merchantTitle: String {
    let merchant = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return merchant.isEmpty ? "Receipt" : merchant
  }

  /// Whether `person` may be on the receipt, which only its split can confirm.
  func mayInclude(_ person: Person) -> Bool {
    hasUnlinkedPeople || personIDs.contains(person.id)
  }

  /// A receipt whose stored file couldn't be read, dated by `date`.
  static func unavailable(id: UUID, date: Date, error: any Error) -> ReceiptSummary {
    ReceiptSummary(
      id: id,
      updatedAt: date,
      capturedAt: date,
      backgroundStyle: .blue,
      recognitionStatus: .failed,
      merchantName: nil,
      localDate: nil,
      total: nil,
      currency: nil,
      isUnavailable: true,
      unavailableDescription: error.localizedDescription)
  }

  /// A new receipt that is being read before storage lists it.
  static func reading(
    id: UUID,
    capturedAt: Date,
    backgroundStyle: ReceiptBackgroundStyle
  ) -> ReceiptSummary {
    ReceiptSummary(
      id: id,
      updatedAt: capturedAt,
      capturedAt: capturedAt,
      backgroundStyle: backgroundStyle,
      recognitionStatus: .pending,
      merchantName: nil,
      localDate: nil,
      total: nil,
      currency: nil,
      isUnavailable: false,
      unavailableDescription: nil)
  }
}

extension ReceiptSummary {
  /// The summary of a stored `document`.
  init(_ document: ReceiptDocument) throws {
    self.init(
      id: document.id,
      updatedAt: document.updatedAt,
      capturedAt: document.scan.capturedAt,
      backgroundStyle: document.presentation.backgroundStyle,
      recognitionStatus: document.recognition.status,
      merchantName: document.receipt?.merchant.name,
      localDate: document.receipt?.transaction.localDate,
      total: try document.receipt.map { try $0.amounts.total.requiredDouble() },
      currency: document.receipt?.currency,
      isUnavailable: false,
      unavailableDescription: nil,
      deferredUntil: document.recognition.status == .succeeded
        ? nil : document.recognition.deferredUntil,
      personIDs: document.split?.personIDs ?? [],
      hasUnlinkedPeople: document.split?.hasUnlinkedPeople ?? false)
  }
}

struct DeletedReceiptSummary: Equatable, Identifiable, Sendable {
  let receipt: ReceiptSummary
  let deletedAt: Date

  /// How long a deleted receipt stays in Recently Deleted.
  static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

  var id: ReceiptSummary.ID { receipt.id }

  /// When the receipt is permanently deleted.
  var expiresAt: Date { deletedAt.addingTimeInterval(Self.retentionInterval) }
}
