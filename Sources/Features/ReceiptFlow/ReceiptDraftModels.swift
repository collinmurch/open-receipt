import Foundation

nonisolated struct ReceiptDraftItem: Identifiable, Equatable, Sendable {
  let id: UUID
  var description: String
  var quantity: Double
  var lineTotal: Money
  var participantIDs: Set<ReceiptParticipant.ID>

  init(item: ReceiptItem) {
    id = UUID()
    description = item.description
    quantity = item.quantity
    lineTotal = item.lineTotal
    participantIDs = []
  }

  init(
    id: UUID,
    description: String,
    quantity: Double,
    lineTotal: Money,
    participantIDs: Set<ReceiptParticipant.ID>
  ) {
    self.id = id
    self.description = description
    self.quantity = quantity
    self.lineTotal = lineTotal
    self.participantIDs = participantIDs
  }
}

nonisolated struct ReceiptParticipant: Identifiable, Equatable, Sendable {
  enum Source: Equatable, Sendable {
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
  var lastRequestedAt: Date?

  init(
    id: UUID,
    personID: UUID? = nil,
    source: Source,
    displayName: String,
    lastRequestedAt: Date? = nil
  ) {
    self.id = id
    self.personID = personID
    self.source = source
    self.displayName = displayName
    self.lastRequestedAt = lastRequestedAt
  }

  static let defaultCurrentUserName = "Me"

  static func currentUser(owner: ReceiptOwner? = nil) -> ReceiptParticipant {
    ReceiptParticipant(
      id: UUID(),
      source: .currentUser(contactIdentifier: owner?.contactIdentifier),
      displayName: owner?.displayName ?? defaultCurrentUserName)
  }
}
