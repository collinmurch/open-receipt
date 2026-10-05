import Foundation

struct ReceiptItemShare: Identifiable, Equatable {
  let itemID: ReceiptDraftItem.ID
  let description: String
  let fraction: Double
  let amount: Double

  var id: ReceiptDraftItem.ID { itemID }
}

struct ReceiptAdjustmentShare: Identifiable, Equatable {
  let id: String
  let title: String
  let fraction: Double
  let amount: Double
}

struct ReceiptParticipantShare: Identifiable, Equatable {
  let participant: ReceiptParticipant
  let items: [ReceiptItemShare]
  let adjustments: [ReceiptAdjustmentShare]

  var id: ReceiptParticipant.ID { participant.id }

  var itemSubtotal: Double {
    items.reduce(0) { $0 + $1.amount }
  }

  var total: Double {
    itemSubtotal + adjustments.reduce(0) { $0 + $1.amount }
  }

  /// How many items the share includes, such as "3 items".
  var itemCountText: String {
    String(inflecting: "^[\(items.count) item](inflect: true)")
  }
}

extension Double {
  /// A fraction of a receipt as a percentage, with at most one decimal place.
  var sharePercentText: String {
    formatted(.percent.precision(.fractionLength(0...1)))
  }
}

struct ReceiptSplitCalculation {
  let participantShares: [ReceiptParticipantShare]
  /// Each participant's share total, by participant.
  let amountsOwed: [ReceiptParticipant.ID: Double]
  let unassignedItemCount: Int
  let unassignedItemTotal: Double
}

enum ReceiptSplitCalculator {
  @MainActor
  static func calculate(
    draft: ReceiptDraft,
    adjustmentMethod: ReceiptAdjustmentSplitMethod
  ) -> ReceiptSplitCalculation {
    let participants = draft.participants
    let participantIDs = participants.map(\.id)
    var itemShares: [ReceiptParticipant.ID: [ReceiptItemShare]] = [:]
    var itemSubtotals: [ReceiptParticipant.ID: Double] = [:]
    var unassignedItemCount = 0
    var unassignedItemTotal = 0.0

    for item in draft.items {
      let assignedIDs = participantIDs.filter { item.participantIDs.contains($0) }
      guard !assignedIDs.isEmpty else {
        unassignedItemCount += 1
        unassignedItemTotal += item.lineTotal
        continue
      }

      let amounts = allocate(item.lineTotal, weights: assignedIDs.map { (id: $0, weight: 1) })
      for participantID in assignedIDs {
        let amount = amounts[participantID, default: 0]
        itemShares[participantID, default: []].append(
          ReceiptItemShare(
            itemID: item.id,
            description: item.description,
            fraction: 1 / Double(assignedIDs.count),
            amount: amount))
        itemSubtotals[participantID, default: 0] += amount
      }
    }

    let weights = adjustmentWeights(
      participantIDs: participantIDs,
      itemSubtotals: itemSubtotals,
      method: adjustmentMethod)
    let weightsByID = Dictionary(uniqueKeysWithValues: weights.map { ($0.id, $0.weight) })
    let totalWeight = weights.reduce(0) { $0 + $1.weight }
    var adjustmentShares: [ReceiptParticipant.ID: [ReceiptAdjustmentShare]] = [:]

    for component in adjustmentComponents(draft: draft) {
      let amounts = allocate(component.amount, weights: weights)
      for participantID in participantIDs {
        guard let amount = amounts[participantID] else { continue }
        let weight = weightsByID[participantID, default: 0]
        adjustmentShares[participantID, default: []].append(
          ReceiptAdjustmentShare(
            id: component.id,
            title: component.title,
            fraction: totalWeight > 0 ? weight / totalWeight : 0,
            amount: amount))
      }
    }

    let shares = participants.map { participant in
      ReceiptParticipantShare(
        participant: participant,
        items: itemShares[participant.id, default: []],
        adjustments: adjustmentShares[participant.id, default: []])
    }
    return ReceiptSplitCalculation(
      participantShares: shares,
      amountsOwed: Dictionary(uniqueKeysWithValues: shares.map { ($0.id, $0.total) }),
      unassignedItemCount: unassignedItemCount,
      unassignedItemTotal: unassignedItemTotal)
  }

  private typealias Weight = (id: ReceiptParticipant.ID, weight: Double)

  private static func adjustmentWeights(
    participantIDs: [ReceiptParticipant.ID],
    itemSubtotals: [ReceiptParticipant.ID: Double],
    method: ReceiptAdjustmentSplitMethod
  ) -> [Weight] {
    switch method {
    case .proportional:
      participantIDs.map { (id: $0, weight: max(0, itemSubtotals[$0, default: 0])) }
    case .even:
      participantIDs.map { (id: $0, weight: 1) }
    }
  }

  /// The amounts between the item subtotal and the total that everyone shares: a printed
  /// subtotal that differs from the items, each adjustment, and anything else the total
  /// includes.
  @MainActor
  private static func adjustmentComponents(draft: ReceiptDraft) -> [AdjustmentComponent] {
    var components: [AdjustmentComponent] = []
    let subtotalDifference = draft.subtotal - draft.expectedSubtotal
    if subtotalDifference.isNonzeroInCents {
      components.append(
        AdjustmentComponent(
          id: "subtotal-adjustment",
          title: "Subtotal adjustment",
          amount: subtotalDifference))
    }
    for adjustment in ReceiptTotalAdjustment.allCases {
      let amount = draft.signedAmount(of: adjustment)
      guard amount.isNonzeroInCents else { continue }
      components.append(
        AdjustmentComponent(id: adjustment.rawValue, title: adjustment.title, amount: amount))
    }

    let knownTotal = draft.subtotal + draft.tax + draft.tip - draft.savings
    let otherDifference = draft.total - knownTotal
    if otherDifference.isNonzeroInCents {
      components.append(
        AdjustmentComponent(id: "other", title: "Other", amount: otherDifference))
    }
    return components
  }

  /// Splits `amount` into whole cents by weight. Leftover cents go to the largest remainders,
  /// and ties go to whoever comes first.
  private static func allocate(
    _ amount: Double,
    weights: [Weight]
  ) -> [ReceiptParticipant.ID: Double] {
    let positiveWeights = weights.filter { $0.weight > 0 }
    let totalWeight = positiveWeights.reduce(0) { $0 + $1.weight }
    guard totalWeight > 0 else { return [:] }

    let sign = amount < 0 ? -1 : 1
    let totalCents = Int((abs(amount) * 100).rounded())
    var cents: [ReceiptParticipant.ID: Int] = [:]
    var remainders: [(order: Int, id: ReceiptParticipant.ID, fraction: Double)] = []
    var allocatedCents = 0

    for (order, entry) in positiveWeights.enumerated() {
      let exactCents = Double(totalCents) * entry.weight / totalWeight
      let baseCents = Int(exactCents.rounded(.down))
      cents[entry.id] = baseCents
      allocatedCents += baseCents
      remainders.append((order: order, id: entry.id, fraction: exactCents - Double(baseCents)))
    }

    remainders.sort {
      $0.fraction == $1.fraction ? $0.order < $1.order : $0.fraction > $1.fraction
    }
    for remainder in remainders.prefix(totalCents - allocatedCents) {
      cents[remainder.id, default: 0] += 1
    }

    return cents.mapValues { Double($0 * sign) / 100 }
  }

  private struct AdjustmentComponent {
    let id: String
    let title: String
    let amount: Double
  }
}
