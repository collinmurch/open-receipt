import Foundation

struct ReceiptDraftPersistenceState {
  let id: UUID
  let backgroundStyle: ReceiptBackgroundStyle
  let merchantName: String
  let date: String
  let subtotal: Double
  let adjustments: ReceiptTotalAdjustments
  let total: Double
  let currency: String
  let payment: ReceiptPayment?
  let items: [ReceiptDraftItem]
  let adjustmentSplitMethod: ReceiptAdjustmentSplitMethod
  let isCompleted: Bool
  let participants: [ReceiptParticipant]
  let extractionWarnings: [String]

  init(document: ReceiptDocument) throws {
    guard let receipt = document.receipt, let split = document.split else {
      throw ReceiptDocumentError.missingReceipt
    }

    func decimal(_ value: DecimalString) throws -> Double {
      guard let result = value.doubleValue else {
        throw ReceiptDocumentError.invalidDecimal(value.value)
      }
      return result
    }

    id = document.id
    backgroundStyle = document.presentation.backgroundStyle
    merchantName = receipt.merchant.name
    date = receipt.transaction.localDate
    subtotal = try decimal(receipt.amounts.subtotal)
    var loadedAdjustments = ReceiptTotalAdjustments()
    for adjustment in receipt.amounts.adjustments {
      let value = try decimal(adjustment.amount)
      loadedAdjustments[adjustment.kind] = adjustment.kind == .savings ? abs(value) : value
    }
    adjustments = loadedAdjustments
    total = try decimal(receipt.amounts.total)
    currency = receipt.currency
    payment = receipt.payment.map {
      ReceiptPayment(
        method: $0.method,
        last4: $0.lastFour,
        authCode: $0.authorizationCode)
    }
    let assignments = Dictionary(
      uniqueKeysWithValues: split.itemAssignments.map {
        ($0.itemID, Set($0.participantIDs))
      })
    items = try receipt.items.map { item in
      ReceiptDraftItem(
        id: item.id,
        description: item.description,
        quantity: try decimal(item.quantity),
        lineTotal: try decimal(item.lineTotal),
        participantIDs: assignments[item.id, default: []])
    }
    adjustmentSplitMethod = split.adjustmentMethod
    isCompleted = document.presentation.isCompleted
    participants = split.participants.map { participant in
      ReceiptParticipant(
        id: participant.id,
        personID: participant.personID,
        source: ReceiptParticipant.Source(participant.source),
        displayName: participant.displayName,
        avatarData: nil,
        lastRequestedAt: participant.lastRequestedAt)
    }
    extractionWarnings = document.recognition.warnings
  }
}

extension ReceiptParticipant.Source {
  init(_ source: ReceiptDocument.ParticipantSource) {
    switch source.type {
    case .currentUser:
      self = .currentUser(contactIdentifier: source.identifier)
    case .contact:
      self = .contact(identifier: source.identifier ?? "")
    case .manual:
      self = .manual
    }
  }

  var documentSource: ReceiptDocument.ParticipantSource {
    switch self {
    case .currentUser(let identifier):
      ReceiptDocument.ParticipantSource(type: .currentUser, identifier: identifier)
    case .contact(let identifier):
      ReceiptDocument.ParticipantSource(type: .contact, identifier: identifier)
    case .manual:
      ReceiptDocument.ParticipantSource(type: .manual, identifier: nil)
    }
  }
}

extension ReceiptDocument {
  @MainActor
  func updating(from draft: ReceiptDraft, at date: Date = Date()) -> ReceiptDocument {
    var document = self
    document.schemaVersion = ReceiptDocument.currentSchemaVersion
    document.updatedAt = date
    document.presentation.backgroundStyle = draft.backgroundStyle
    document.presentation.isCompleted = draft.isCompleted
    document.recognition.status = .succeeded
    document.recognition.lastAttemptedAt = document.recognition.lastAttemptedAt ?? date
    document.recognition.completedAt = document.recognition.completedAt ?? date
    document.recognition.failureMessage = nil
    document.receipt = Receipt(
      merchant: Merchant(name: draft.merchantName),
      transaction: Transaction(localDate: draft.date),
      currency: draft.currency,
      items: draft.items.map {
        Item(
          id: $0.id,
          description: $0.description,
          quantity: DecimalString($0.quantity),
          lineTotal: DecimalString($0.lineTotal))
      },
      amounts: Amounts(
        subtotal: DecimalString(draft.subtotal),
        adjustments: ReceiptTotalAdjustment.allCases.compactMap { kind in
          guard let value = draft.adjustments[kind] else { return nil }
          let signedValue = kind == .savings ? -abs(value) : value
          return Adjustment(
            id: kind.rawValue,
            kind: kind,
            label: kind.title,
            amount: DecimalString(signedValue))
        },
        total: DecimalString(draft.total)),
      payment: draft.payment.map {
        Payment(
          method: $0.method,
          lastFour: $0.last4,
          authorizationCode: $0.authCode)
      })
    document.split = Split(
      adjustmentMethod: draft.adjustmentSplitMethod,
      participants: draft.participants.map {
        Participant(
          id: $0.id,
          personID: $0.personID,
          displayName: $0.displayName,
          source: $0.source.documentSource,
          lastRequestedAt: $0.lastRequestedAt)
      },
      itemAssignments: draft.items.map {
        ItemAssignment(
          itemID: $0.id,
          participantIDs: $0.participantIDs.sorted { $0.uuidString < $1.uuidString })
      })
    return document
  }
}
