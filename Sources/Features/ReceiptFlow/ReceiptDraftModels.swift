import Foundation

struct ReceiptTotalAdjustments: Equatable {
  private var amounts: [ReceiptTotalAdjustment: Double]

  init(tax: Double = 0, tip: Double = 0, savings: Double = 0) {
    amounts = [:]
    if tax != 0 { amounts[.tax] = tax }
    if tip != 0 { amounts[.tip] = tip }
    if savings != 0 { amounts[.savings] = savings }
  }

  subscript(_ adjustment: ReceiptTotalAdjustment) -> Double? {
    get { amounts[adjustment] }
    set { amounts[adjustment] = newValue }
  }

  var isEmpty: Bool {
    amounts.isEmpty
  }

  var missing: [ReceiptTotalAdjustment] {
    ReceiptTotalAdjustment.allCases.filter { amounts[$0] == nil }
  }

  func contains(_ adjustment: ReceiptTotalAdjustment) -> Bool {
    amounts[adjustment] != nil
  }

  mutating func add(_ adjustment: ReceiptTotalAdjustment) {
    if amounts[adjustment] == nil {
      amounts[adjustment] = 0
    }
  }

  mutating func remove(_ adjustment: ReceiptTotalAdjustment) {
    amounts[adjustment] = nil
  }
}

struct ReceiptDraftItem: Identifiable, Equatable {
  let id: UUID
  var description: String
  var quantity: Double
  var lineTotal: Double
  var participantIDs: Set<ReceiptParticipant.ID>

  init(item: ReceiptItem, id: UUID = UUID()) {
    self.id = id
    description = item.description
    quantity = item.quantity
    lineTotal = item.lineTotal
    participantIDs = []
  }

  init(
    id: UUID,
    description: String,
    quantity: Double,
    lineTotal: Double,
    participantIDs: Set<ReceiptParticipant.ID>
  ) {
    self.id = id
    self.description = description
    self.quantity = quantity
    self.lineTotal = lineTotal
    self.participantIDs = participantIDs
  }
}

struct ReceiptParticipant: Identifiable, Equatable {
  enum Source: Equatable {
    case currentUser(contactIdentifier: String?)
    case contact(identifier: String)
    case manual

    var isCurrentUser: Bool {
      if case .currentUser = self { return true }
      return false
    }

    var contactIdentifier: String? {
      switch self {
      case .currentUser(let identifier): identifier
      case .contact(let identifier): identifier
      case .manual: nil
      }
    }
  }

  let id: UUID
  let personID: UUID?
  var source: Source
  var displayName: String
  var avatarData: Data?
  var lastRequestedAt: Date?

  init(
    id: UUID,
    personID: UUID? = nil,
    source: Source,
    displayName: String,
    avatarData: Data?,
    lastRequestedAt: Date? = nil
  ) {
    self.id = id
    self.personID = personID
    self.source = source
    self.displayName = displayName
    self.avatarData = avatarData
    self.lastRequestedAt = lastRequestedAt
  }

  static let defaultCurrentUserName = "Me"

  static func currentUser(id: UUID = UUID(), owner: ReceiptOwner? = nil) -> ReceiptParticipant {
    ReceiptParticipant(
      id: id,
      source: .currentUser(contactIdentifier: owner?.contactIdentifier),
      displayName: owner?.displayName ?? defaultCurrentUserName,
      avatarData: nil)
  }
}
