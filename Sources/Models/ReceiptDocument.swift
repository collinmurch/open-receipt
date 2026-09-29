import Foundation

struct ReceiptDocument: Codable, Equatable, Identifiable, Sendable {
  static let currentSchemaVersion = 4

  var schemaVersion: Int
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  var presentation: Presentation
  var scan: Scan
  var recognition: Recognition
  var receipt: Receipt?
  var split: Split?

  /// Whether pages were added or removed since the receipt values were recognized.
  var needsRescan: Bool {
    !scan.pages.isEmpty && Set(scan.pages.map(\.id)) != Set(recognition.pageIDs)
  }

  struct Presentation: Codable, Equatable, Sendable {
    var backgroundStyle: ReceiptBackgroundStyle
    var isCompleted: Bool

    init(backgroundStyle: ReceiptBackgroundStyle, isCompleted: Bool = false) {
      self.backgroundStyle = backgroundStyle
      self.isCompleted = isCompleted
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      backgroundStyle = try container.decode(ReceiptBackgroundStyle.self, forKey: .backgroundStyle)
      isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }
  }

  struct Scan: Codable, Equatable, Sendable {
    let capturedAt: Date
    let source: ReceiptScan.Source
    var pages: [Page]
  }

  struct Page: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let file: String
    let mediaType: String
  }

  struct Recognition: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
      case pending
      case succeeded
      case failed
    }

    var status: Status
    var contractVersion: Int
    var lastAttemptedAt: Date?
    var completedAt: Date?
    var warnings: [String]
    var failureMessage: String?
    /// The scan pages the current receipt values were recognized from.
    var pageIDs: [UUID] = []
    /// When a read that stopped at the reading limit starts again on its own.
    var deferredUntil: Date?

    enum CodingKeys: String, CodingKey {
      case status
      case contractVersion
      case lastAttemptedAt
      case completedAt
      case warnings
      case failureMessage
      case pageIDs = "pageIds"
      case deferredUntil
    }
  }

  struct Receipt: Codable, Equatable, Sendable {
    var merchant: Merchant
    var transaction: Transaction
    var currency: String
    var items: [Item]
    var amounts: Amounts
    var payment: Payment?
  }

  struct Merchant: Codable, Equatable, Sendable {
    var name: String
  }

  struct Transaction: Codable, Equatable, Sendable {
    var localDate: String
  }

  struct Item: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var description: String
    var quantity: DecimalString
    var lineTotal: DecimalString
  }

  struct Amounts: Codable, Equatable, Sendable {
    var subtotal: DecimalString
    var adjustments: [Adjustment]
    var total: DecimalString
  }

  struct Adjustment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: ReceiptTotalAdjustment
    var label: String
    var amount: DecimalString
  }

  struct Payment: Codable, Equatable, Sendable {
    var method: String?
    var lastFour: String?
    var authorizationCode: String?
  }

  struct Split: Codable, Equatable, Sendable {
    var adjustmentMethod: ReceiptAdjustmentSplitMethod
    var participants: [Participant]
    var itemAssignments: [ItemAssignment]
  }

  struct Participant: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var personID: UUID? = nil
    var displayName: String
    let source: ParticipantSource
    var lastRequestedAt: Date? = nil

    enum CodingKeys: String, CodingKey {
      case id
      case personID = "personId"
      case displayName
      case source
      case lastRequestedAt
    }
  }

  struct ParticipantSource: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
      case currentUser
      case contact
      case manual
    }

    let type: Kind
    let identifier: String?
  }

  struct ItemAssignment: Codable, Equatable, Sendable {
    let itemID: UUID
    var participantIDs: [UUID]

    enum CodingKeys: String, CodingKey {
      case itemID = "itemId"
      case participantIDs = "participantIds"
    }
  }
}

struct DecimalString: Codable, Equatable, Sendable {
  let value: String

  init(_ value: Double) {
    self.value = String(value)
  }

  var doubleValue: Double? {
    Double(value).flatMap { $0.isFinite ? $0 : nil }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let number = Double(value), number.isFinite else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected a finite decimal string.")
    }
    self.value = value
  }

  func encode(to encoder: Encoder) throws {
    guard let number = Double(value), number.isFinite else {
      throw EncodingError.invalidValue(
        value,
        EncodingError.Context(
          codingPath: encoder.codingPath,
          debugDescription: "Expected a finite decimal string."))
    }
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

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
}

enum ReceiptDocumentError: Error, LocalizedError, Equatable {
  case unsupportedSchemaVersion(Int)
  case missingReceipt
  case invalidDecimal(String)
  case invalidPagePath(String)

  var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version) where version < ReceiptDocument.currentSchemaVersion:
      "This receipt was saved by an older version of Open Receipt and can no longer be opened."
    case .unsupportedSchemaVersion(let version):
      "Receipt schema version \(version) is not supported."
    case .missingReceipt:
      "The saved receipt does not contain parsed receipt data."
    case .invalidDecimal(let value):
      "The saved receipt contains an invalid decimal value: \(value)."
    case .invalidPagePath(let path):
      "The saved receipt contains an invalid page path: \(path)."
    }
  }
}
