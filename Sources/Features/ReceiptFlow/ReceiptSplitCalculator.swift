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
}

enum ReceiptSplitCalculator {
  /// Splits `draft` in whole units of its currency, so every share is an amount that can be paid
  /// and the shares add up to exactly what was split.
  @MainActor
  static func calculate(
    draft: ReceiptDraft,
    adjustmentMethod: ReceiptAdjustmentSplitMethod
  ) -> ReceiptSplitCalculation {
    let currency = draft.displayCurrency
    let participants = draft.participants
    let participantIDs = participants.map(\.id)
    var ledger = Ledger()
    var itemShares: [ReceiptParticipant.ID: [ReceiptItemShare]] = [:]
    var itemSubtotals: [ReceiptParticipant.ID: Double] = [:]
    var unassignedItemCount = 0

    for item in draft.items {
      let assignedIDs = participantIDs.filter { item.participantIDs.contains($0) }
      guard !assignedIDs.isEmpty else {
        unassignedItemCount += 1
        continue
      }

      let lineUnits = ReceiptCurrency.minorUnits(item.lineTotal, code: currency)
      let allocation = ledger.allocate(
        lineUnits, weights: assignedIDs.map { (id: $0, weight: 1) })
      for participantID in assignedIDs {
        let units = allocation[participantID, default: 0]
        itemShares[participantID, default: []].append(
          ReceiptItemShare(
            itemID: item.id,
            description: item.description,
            fraction: 1 / Double(assignedIDs.count),
            amount: ReceiptCurrency.amount(minorUnits: units, code: currency)))
        itemSubtotals[participantID, default: 0] += Double(lineUnits) / Double(assignedIDs.count)
      }
    }

    let weights = adjustmentWeights(
      participantIDs: participantIDs,
      itemSubtotals: itemSubtotals,
      method: adjustmentMethod)
    let weightsByID = Dictionary(uniqueKeysWithValues: weights.map { ($0.id, $0.weight) })
    let totalWeight = weights.reduce(0) { $0 + $1.weight }
    var adjustmentShares: [ReceiptParticipant.ID: [ReceiptAdjustmentShare]] = [:]

    for component in adjustmentComponents(draft: draft, currency: currency) {
      let allocation = ledger.allocate(component.units, weights: weights)
      for participantID in participantIDs {
        guard let units = allocation[participantID] else { continue }
        let weight = weightsByID[participantID, default: 0]
        adjustmentShares[participantID, default: []].append(
          ReceiptAdjustmentShare(
            id: component.id,
            title: component.title,
            fraction: totalWeight > 0 ? weight / totalWeight : 0,
            amount: ReceiptCurrency.amount(minorUnits: units, code: currency)))
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
      unassignedItemCount: unassignedItemCount)
  }

  private typealias Weight = (id: ReceiptParticipant.ID, weight: Double)

  /// How the shared amounts are weighted. A proportional split with no positive item subtotals
  /// to follow is even, so the shared amounts are still paid.
  private static func adjustmentWeights(
    participantIDs: [ReceiptParticipant.ID],
    itemSubtotals: [ReceiptParticipant.ID: Double],
    method: ReceiptAdjustmentSplitMethod
  ) -> [Weight] {
    let even = participantIDs.map { (id: $0, weight: 1.0) }
    switch method {
    case .proportional:
      let proportional = participantIDs.map {
        (id: $0, weight: max(0, itemSubtotals[$0, default: 0]))
      }
      return proportional.contains { $0.weight > 0 } ? proportional : even
    case .even:
      return even
    }
  }

  /// The amounts between the item subtotal and the total that everyone shares: a printed
  /// subtotal that differs from the items, each adjustment, and anything else the total
  /// includes. They are counted in whole units, so together with the items they add up to
  /// exactly the total.
  @MainActor
  private static func adjustmentComponents(
    draft: ReceiptDraft,
    currency: String
  ) -> [AdjustmentComponent] {
    func units(_ amount: Double) -> Int {
      ReceiptCurrency.minorUnits(amount, code: currency)
    }
    var components: [AdjustmentComponent] = []
    let subtotalUnits = units(draft.subtotal)
    let itemUnits = draft.items.reduce(0) { $0 + units($1.lineTotal) }
    if subtotalUnits != itemUnits {
      components.append(
        AdjustmentComponent(
          id: "subtotal-adjustment",
          title: "Subtotal adjustment",
          units: subtotalUnits - itemUnits))
    }

    var knownUnits = subtotalUnits
    for adjustment in ReceiptTotalAdjustment.allCases {
      let adjustmentUnits = units(draft.signedAmount(of: adjustment))
      knownUnits += adjustmentUnits
      guard adjustmentUnits != 0 else { continue }
      components.append(
        AdjustmentComponent(id: adjustment.rawValue, title: adjustment.title, units: adjustmentUnits))
    }

    let otherUnits = units(draft.total) - knownUnits
    if otherUnits != 0 {
      components.append(AdjustmentComponent(id: "other", title: "Other", units: otherUnits))
    }
    return components
  }

  /// Splits amounts in whole units across a receipt, tracking how far each participant's
  /// allocation is from their exact share. Each amount's leftover units go to whoever is furthest
  /// behind, with ties going to whoever comes first, so rounding evens out over the receipt
  /// instead of landing on the same person every time.
  private struct Ledger {
    /// Each participant's exact share minus what they've been allocated, in units.
    private var balances: [ReceiptParticipant.ID: Double] = [:]

    mutating func allocate(_ units: Int, weights: [Weight]) -> [ReceiptParticipant.ID: Int] {
      let positiveWeights = weights.filter { $0.weight > 0 }
      let totalWeight = positiveWeights.reduce(0) { $0 + $1.weight }
      guard totalWeight > 0 else { return [:] }

      let sign = units < 0 ? -1 : 1
      let magnitude = abs(units)
      var allocation: [ReceiptParticipant.ID: Int] = [:]
      var candidates: [(order: Int, id: ReceiptParticipant.ID, shortfall: Double)] = []
      var allocatedUnits = 0

      for (order, entry) in positiveWeights.enumerated() {
        let exact = Double(magnitude) * entry.weight / totalWeight
        let base = Int(exact.rounded(.down))
        let remainder = exact - Double(base)
        allocation[entry.id] = base
        allocatedUnits += base
        let balance = balances[entry.id, default: 0]
        candidates.append(
          (order: order, id: entry.id, shortfall: Double(sign) * balance + remainder))
        balances[entry.id] = balance + Double(sign) * remainder
      }

      candidates.sort {
        abs($0.shortfall - $1.shortfall) < 1e-9
          ? $0.order < $1.order : $0.shortfall > $1.shortfall
      }
      for candidate in candidates.prefix(magnitude - allocatedUnits) {
        allocation[candidate.id, default: 0] += 1
        balances[candidate.id, default: 0] -= Double(sign)
      }

      return allocation.mapValues { $0 * sign }
    }
  }

  private struct AdjustmentComponent {
    let id: String
    let title: String
    let units: Int
  }
}
