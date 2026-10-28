import Foundation

nonisolated struct ReceiptItemShare: Identifiable, Equatable {
  let itemID: ReceiptDraftItem.ID
  let description: String
  let quantity: Double
  let fraction: Double
  let amount: Money

  var id: ReceiptDraftItem.ID { itemID }
}

nonisolated struct ReceiptAdjustmentShare: Identifiable, Equatable {
  let id: String
  let title: String
  let fraction: Double
  let amount: Money
}

nonisolated struct ReceiptParticipantShare: Identifiable, Equatable {
  let participant: ReceiptParticipant
  let items: [ReceiptItemShare]
  let adjustments: [ReceiptAdjustmentShare]
  /// What the share comes to, in the currency's smallest unit.
  let units: Int
  /// What the share comes to.
  let total: Money

  var id: ReceiptParticipant.ID { participant.id }

  /// How many items the share includes, counting each item's quantity. A quantity that isn't a
  /// whole number, such as a weight, counts as one item.
  var itemCount: Int {
    items.reduce(0) { count, item in
      let isWholeCount =
        item.quantity.isFinite && item.quantity >= 1 && item.quantity.rounded() == item.quantity
      return count + (isWholeCount ? Int(item.quantity) : 1)
    }
  }

  /// How many items the share includes, such as "3 items".
  var itemCountText: String {
    String(inflecting: "^[\(itemCount) item](inflect: true)")
  }
}

nonisolated extension Double {
  /// A fraction of a receipt as a percentage, with at most one decimal place.
  var sharePercentText: String {
    formatted(.percent.precision(.fractionLength(0...1)))
  }
}

/// The values a receipt's split is worked out from.
nonisolated struct ReceiptSplitInput: Sendable {
  var items: [ReceiptDraftItem]
  var participants: [ReceiptParticipant]
  var subtotal: Money
  var adjustments: ReceiptTotalAdjustments
  var total: Money
  /// The currency whose smallest unit amounts are split in.
  var currency: String
  var adjustmentMethod: ReceiptAdjustmentSplitMethod
}

nonisolated struct ReceiptSplitCalculation: Sendable {
  let participantShares: [ReceiptParticipantShare]
  /// Each participant's share total, by participant.
  let amountsOwed: [ReceiptParticipant.ID: Money]
  let unassignedItemCount: Int
}

nonisolated enum ReceiptSplitCalculator {
  /// Splits `input` in whole units of its currency, so every share is an amount that can be paid
  /// and the shares add up to exactly what was split. `balance` is `input`'s balance, when it's
  /// already known.
  static func calculate(
    _ input: ReceiptSplitInput, balance: ReceiptBalance? = nil
  ) -> ReceiptSplitCalculation {
    assert(balance == nil || balance == ReceiptBalance(input), "The balance is the input's")
    let currency = input.currency
    let participants = input.participants
    func units(_ amount: Money) -> Int {
      ReceiptCurrency.minorUnits(amount, code: currency)
    }
    func amount(_ units: Int) -> Money {
      ReceiptCurrency.amount(minorUnits: units, code: currency)
    }

    let itemLines = input.items.compactMap { item -> (item: ReceiptDraftItem, line: Line)? in
      let sharers = participants.indices.filter {
        item.participantIDs.contains(participants[$0].id)
      }
      return Line(units: units(item.lineTotal), weights: sharers.map { ($0, 1) }).map { (item, $0) }
    }
    let weights = adjustmentWeights(
      itemLines.map(\.line), participantCount: participants.count, method: input.adjustmentMethod)
    let componentLines = adjustmentComponents(of: input, balance: balance ?? ReceiptBalance(input))
      .compactMap { component -> (component: AdjustmentComponent, line: Line)? in
        Line(units: component.units, weights: weights).map { (component, $0) }
      }
    let allocation = SplitRounding.allocate(
      itemLines.map(\.line) + componentLines.map(\.line),
      participantCount: participants.count,
      last: participants.firstIndex { $0.source.isCurrentUser })

    var itemShares = Array(repeating: [ReceiptItemShare](), count: participants.count)
    var adjustmentShares = Array(repeating: [ReceiptAdjustmentShare](), count: participants.count)
    var totals = Array(repeating: 0, count: participants.count)
    for ((item, line), lineUnits) in zip(itemLines, allocation) {
      for (index, share) in line.shares.enumerated() {
        itemShares[share.participant].append(
          ReceiptItemShare(
            itemID: item.id,
            description: item.description,
            quantity: item.quantity,
            fraction: line.fraction(at: index),
            amount: amount(lineUnits[index])))
        totals[share.participant] += lineUnits[index]
      }
    }
    for ((component, line), lineUnits) in zip(componentLines, allocation.dropFirst(itemLines.count))
    {
      for (index, share) in line.shares.enumerated() {
        adjustmentShares[share.participant].append(
          ReceiptAdjustmentShare(
            id: component.id,
            title: component.title,
            fraction: line.fraction(at: index),
            amount: amount(lineUnits[index])))
        totals[share.participant] += lineUnits[index]
      }
    }

    let shares = participants.indices.map { index in
      ReceiptParticipantShare(
        participant: participants[index],
        items: itemShares[index],
        adjustments: adjustmentShares[index],
        units: totals[index],
        total: amount(totals[index]))
    }
    return ReceiptSplitCalculation(
      participantShares: shares,
      amountsOwed: Dictionary(
        shares.map { ($0.id, $0.total) }, uniquingKeysWith: { first, _ in first }),
      unassignedItemCount: input.items.count - itemLines.count)
  }

  private typealias Line = SplitRounding.Line

  /// How the shared amounts are weighted: by what each participant's items come to, or evenly. A
  /// proportional split with no positive item subtotals to follow is even, so the shared amounts
  /// are still paid. Item subtotals are counted over a common denominator, so they stay whole.
  private static func adjustmentWeights(
    _ itemLines: [Line],
    participantCount: Int,
    method: ReceiptAdjustmentSplitMethod
  ) -> [(participant: Int, weight: Int128)] {
    let even = (0..<participantCount).map { ($0, Int128(1)) }
    guard method == .proportional else { return even }
    let denominator = SplitRounding.commonDenominator(of: itemLines)
    var subtotals = Array(repeating: Int128(0), count: participantCount)
    for line in itemLines {
      for share in line.shares {
        subtotals[share.participant] +=
          Int128(line.units) * share.weight * (denominator / line.totalWeight)
      }
    }
    return subtotals.contains { $0 > 0 } ? subtotals.enumerated().map { ($0, $1) } : even
  }

  /// The amounts between the items and the total that everyone shares: a printed subtotal that
  /// differs from the items, each adjustment, and anything else the total includes. Savings
  /// already taken off the item prices aren't taken off again. Together with the items they add
  /// up to exactly the total.
  private static func adjustmentComponents(
    of input: ReceiptSplitInput, balance: ReceiptBalance
  ) -> [AdjustmentComponent] {
    let adjustments = ReceiptTotalAdjustment.allCases.compactMap {
      adjustment -> AdjustmentComponent? in
      if adjustment == .savings, !balance.subtractsSavingsFromItems { return nil }
      return AdjustmentComponent(
        id: adjustment.rawValue,
        title: adjustment.title,
        units: ReceiptCurrency.minorUnits(
          input.adjustments.signedAmount(of: adjustment), code: input.currency))
    }
    let components =
      [
        AdjustmentComponent(
          id: "subtotal-adjustment", title: "Subtotal adjustment",
          units: balance.subtotalDifferenceUnits)
      ] + adjustments + [
        AdjustmentComponent(id: "other", title: "Other", units: balance.totalDifferenceUnits)
      ]
    return components.filter { $0.units != 0 }
  }

  private struct AdjustmentComponent {
    let id: String
    let title: String
    let units: Int
  }
}
