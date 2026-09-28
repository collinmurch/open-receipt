import Foundation

enum ReceiptAdjustmentSplitMethod: String, CaseIterable, Codable, Identifiable, Sendable {
  case proportional
  case even

  var id: Self { self }

  var title: String {
    switch self {
    case .proportional: "Proportionally"
    case .even: "Evenly"
    }
  }
}

struct ReceiptItemShare: Identifiable {
  let itemID: ReceiptDraftItem.ID
  let description: String
  let fraction: Double
  let amount: Double

  var id: ReceiptDraftItem.ID { itemID }
}

struct ReceiptAdjustmentShare: Identifiable {
  let id: String
  let title: String
  let fraction: Double
  let amount: Double
}

struct ReceiptParticipantShare: Identifiable {
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
}

struct ReceiptSplitCalculation {
  let participantShares: [ReceiptParticipantShare]
  let unassignedItemCount: Int
  let unassignedItemTotal: Double

  var assignedTotal: Double {
    participantShares.reduce(0) { $0 + $1.total }
  }
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

      let amounts = allocate(item.lineTotal, weights: assignedIDs.map { ($0, 1) })
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
    let totalWeight = weights.reduce(0) { $0 + $1.1 }
    var adjustmentShares: [ReceiptParticipant.ID: [ReceiptAdjustmentShare]] = [:]

    for component in adjustmentComponents(draft: draft) {
      let amounts = allocate(component.amount, weights: weights)
      for participantID in participantIDs {
        guard let amount = amounts[participantID] else { continue }
        let weight = weights.first { $0.0 == participantID }?.1 ?? 0
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
      unassignedItemCount: unassignedItemCount,
      unassignedItemTotal: unassignedItemTotal)
  }

  private static func adjustmentWeights(
    participantIDs: [ReceiptParticipant.ID],
    itemSubtotals: [ReceiptParticipant.ID: Double],
    method: ReceiptAdjustmentSplitMethod
  ) -> [(ReceiptParticipant.ID, Double)] {
    switch method {
    case .proportional:
      participantIDs.map { ($0, max(0, itemSubtotals[$0, default: 0])) }
    case .even:
      participantIDs.map { ($0, 1) }
    }
  }

  @MainActor
  private static func adjustmentComponents(draft: ReceiptDraft) -> [AdjustmentComponent] {
    var components: [AdjustmentComponent] = []
    let itemSubtotal = draft.items.reduce(0) { $0 + $1.lineTotal }
    let subtotalDifference = draft.subtotal - itemSubtotal
    if abs(subtotalDifference) >= 0.005 {
      components.append(
        AdjustmentComponent(
          id: "subtotal-adjustment",
          title: "Subtotal adjustment",
          amount: subtotalDifference))
    }
    if draft.adjustments.contains(.tax), abs(draft.tax) >= 0.005 {
      components.append(AdjustmentComponent(id: "tax", title: "Tax", amount: draft.tax))
    }
    if draft.adjustments.contains(.tip), abs(draft.tip) >= 0.005 {
      components.append(AdjustmentComponent(id: "tip", title: "Tip", amount: draft.tip))
    }
    if draft.adjustments.contains(.savings), abs(draft.savings) >= 0.005 {
      components.append(
        AdjustmentComponent(id: "savings", title: "Savings", amount: -draft.savings))
    }

    let knownTotal = draft.subtotal + draft.tax + draft.tip - draft.savings
    let otherDifference = draft.total - knownTotal
    if abs(otherDifference) >= 0.005 {
      components.append(
        AdjustmentComponent(id: "other", title: "Other", amount: otherDifference))
    }
    return components
  }

  private static func allocate(
    _ amount: Double,
    weights: [(ReceiptParticipant.ID, Double)]
  ) -> [ReceiptParticipant.ID: Double] {
    let positiveWeights = weights.filter { $0.1 > 0 }
    let totalWeight = positiveWeights.reduce(0) { $0 + $1.1 }
    guard totalWeight > 0 else { return [:] }

    let sign = amount < 0 ? -1 : 1
    let totalCents = Int((abs(amount) * 100).rounded())
    var cents: [ReceiptParticipant.ID: Int] = [:]
    var fractions: [(ReceiptParticipant.ID, Double)] = []
    var allocatedCents = 0

    for (participantID, weight) in positiveWeights {
      let exactCents = Double(totalCents) * weight / totalWeight
      let baseCents = Int(exactCents.rounded(.down))
      cents[participantID] = baseCents
      allocatedCents += baseCents
      fractions.append((participantID, exactCents - Double(baseCents)))
    }

    fractions.sort {
      if $0.1 == $1.1 {
        return participantIndex($0.0, in: positiveWeights)
          < participantIndex($1.0, in: positiveWeights)
      }
      return $0.1 > $1.1
    }
    for index in 0..<(totalCents - allocatedCents) {
      cents[fractions[index].0, default: 0] += 1
    }

    return cents.mapValues { Double($0 * sign) / 100 }
  }

  private static func participantIndex(
    _ id: ReceiptParticipant.ID,
    in weights: [(ReceiptParticipant.ID, Double)]
  ) -> Int {
    weights.firstIndex { $0.0 == id } ?? weights.endIndex
  }

  private struct AdjustmentComponent {
    let id: String
    let title: String
    let amount: Double
  }
}
