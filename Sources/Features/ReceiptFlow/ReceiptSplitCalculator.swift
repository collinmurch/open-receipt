import Foundation

struct ReceiptItemShare: Identifiable, Equatable {
  let itemID: ReceiptDraftItem.ID
  let description: String
  let quantity: Double
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

extension Double {
  /// A fraction of a receipt as a percentage, with at most one decimal place.
  var sharePercentText: String {
    formatted(.percent.precision(.fractionLength(0...1)))
  }
}

/// The values a receipt's split is worked out from.
struct ReceiptSplitInput: Sendable {
  var items: [ReceiptDraftItem]
  var participants: [ReceiptParticipant]
  var subtotal: Double
  var adjustments: ReceiptTotalAdjustments
  var total: Double
  /// The currency whose smallest unit amounts are split in.
  var currency: String
  var adjustmentMethod: ReceiptAdjustmentSplitMethod
}

struct ReceiptSplitCalculation: Sendable {
  let participantShares: [ReceiptParticipantShare]
  /// Each participant's share total, by participant.
  let amountsOwed: [ReceiptParticipant.ID: Double]
  let unassignedItemCount: Int
}

enum ReceiptSplitCalculator {
  /// Splits `input` in whole units of its currency, so every share is an amount that can be paid
  /// and the shares add up to exactly what was split. `balance` is `input`'s balance, when it's
  /// already known.
  static func calculate(
    _ input: ReceiptSplitInput, balance: ReceiptBalance? = nil
  ) -> ReceiptSplitCalculation {
    let currency = input.currency
    let participants = input.participants
    let participantIDs = participants.map(\.id)
    let itemUnits = input.items.map { ReceiptCurrency.minorUnits($0.lineTotal, code: currency) }
    let itemLines = zip(input.items, itemUnits).compactMap {
      item, units -> (item: ReceiptDraftItem, line: Line)? in
      let assignedIDs = participantIDs.filter { item.participantIDs.contains($0) }
      guard !assignedIDs.isEmpty else { return nil }
      return (item, Line(units: units, weights: assignedIDs.map { (id: $0, weight: 1) }))
    }
    var itemSubtotals: [ReceiptParticipant.ID: Double] = [:]
    for (_, line) in itemLines {
      for share in line.shares {
        itemSubtotals[share.id, default: 0] += Double(line.units) * share.fraction
      }
    }

    let weights = adjustmentWeights(
      participantIDs: participantIDs,
      itemSubtotals: itemSubtotals,
      method: input.adjustmentMethod)
    let components = adjustmentComponents(
      of: input, balance: balance ?? ReceiptBalance(input),
      itemUnits: itemUnits.reduce(0, +))
    let componentLines = components.map {
      (component: $0, line: Line(units: $0.units, weights: weights))
    }
    let allocation = allocate(
      itemLines.map(\.line) + componentLines.map(\.line),
      participantIDs: participantIDs,
      ownerID: participants.first { $0.source.isCurrentUser }?.id)

    func amount(_ units: Int) -> Double {
      ReceiptCurrency.amount(minorUnits: units, code: currency)
    }
    var itemShares: [ReceiptParticipant.ID: [ReceiptItemShare]] = [:]
    for ((item, line), lineUnits) in zip(itemLines, allocation) {
      for (share, units) in zip(line.shares, lineUnits) {
        itemShares[share.id, default: []].append(
          ReceiptItemShare(
            itemID: item.id,
            description: item.description,
            quantity: item.quantity,
            fraction: share.fraction,
            amount: amount(units)))
      }
    }
    var adjustmentShares: [ReceiptParticipant.ID: [ReceiptAdjustmentShare]] = [:]
    for ((component, line), lineUnits) in zip(componentLines, allocation.dropFirst(itemLines.count))
    {
      for (share, units) in zip(line.shares, lineUnits) {
        adjustmentShares[share.id, default: []].append(
          ReceiptAdjustmentShare(
            id: component.id,
            title: component.title,
            fraction: share.fraction,
            amount: amount(units)))
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
      unassignedItemCount: input.items.count - itemLines.count)
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

  /// The amounts between the items and the total that everyone shares: a printed subtotal that
  /// differs from the items, each adjustment, and anything else the total includes. Savings
  /// already taken off the item prices aren't taken off again. They are counted in whole units,
  /// so together with the items, which come to `itemUnits`, they add up to exactly the total.
  private static func adjustmentComponents(
    of input: ReceiptSplitInput, balance: ReceiptBalance, itemUnits: Int
  ) -> [AdjustmentComponent] {
    func units(_ amount: Double) -> Int {
      ReceiptCurrency.minorUnits(amount, code: input.currency)
    }
    var components: [AdjustmentComponent] = []
    var knownUnits = itemUnits
    if balance.subtotalDifferenceUnits != 0 {
      knownUnits += balance.subtotalDifferenceUnits
      components.append(
        AdjustmentComponent(
          id: "subtotal-adjustment",
          title: "Subtotal adjustment",
          units: balance.subtotalDifferenceUnits))
    }

    for adjustment in ReceiptTotalAdjustment.allCases {
      if adjustment == .savings, !balance.subtractsSavingsFromItems { continue }
      let adjustmentUnits = units(input.adjustments.signedAmount(of: adjustment))
      knownUnits += adjustmentUnits
      guard adjustmentUnits != 0 else { continue }
      components.append(
        AdjustmentComponent(
          id: adjustment.rawValue, title: adjustment.title, units: adjustmentUnits))
    }

    let otherUnits = units(input.total) - knownUnits
    if otherUnits != 0 {
      components.append(AdjustmentComponent(id: "other", title: "Other", units: otherUnits))
    }
    return components
  }

  /// Splits each line into whole units that add up to the line, rounding every exact share down or
  /// up so that each participant's total is also within one unit of their exact total.
  /// Participants furthest below their exact total are rounded up first, and the owner last, so
  /// they pay a leftover unit last and take a leftover saving first.
  ///
  /// Rounding a share up takes one of its line's leftover units. When a participant's lines have
  /// none left, someone already rounded up on one of them moves to another line of theirs that
  /// does, as in bipartite matching, so whether a participant can be rounded up never depends on
  /// the order lines were placed in.
  private static func allocate(
    _ lines: [Line],
    participantIDs: [ReceiptParticipant.ID],
    ownerID: ReceiptParticipant.ID?
  ) -> [[Int]] {
    let participantIndices = Dictionary(
      participantIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    // Every line's shares, numbered in one run, with whom each is for and its line.
    var lineShares: [Range<Int>] = []
    var sharers: [Int] = []
    var shareLines: [Int] = []
    var floors: [Int] = []
    var openUnits: [Int] = []
    var options = Array(repeating: [(share: Int, fraction: Double)](), count: participantIDs.count)
    var fractions = Array(repeating: 0.0, count: participantIDs.count)
    for (lineIndex, line) in lines.enumerated() {
      let start = floors.count
      for share in line.shares {
        let participant = participantIndices[share.id]!
        let exact = snapped(Double(line.units) * share.fraction)
        let floor = exact.rounded(.down)
        if exact > floor {
          options[participant].append((floors.count, exact - floor))
          fractions[participant] += exact - floor
        }
        sharers.append(participant)
        shareLines.append(lineIndex)
        floors.append(Int(floor))
      }
      lineShares.append(start..<floors.count)
      openUnits.append(line.units - floors[start...].reduce(0, +))
    }
    var isRoundedUp = Array(repeating: false, count: floors.count)
    // Each participant's shares, largest fraction first, are rounded up first.
    let shareOptions = options.map { $0.sorted { $0.fraction > $1.fraction }.map(\.share) }
    // A share that's rounded up or whose line is full never becomes free again, since searches
    // only take shares back on full lines, so each participant's free shares are found from where
    // the last search left off.
    var nextFree = Array(repeating: 0, count: participantIDs.count)

    // Each search visits every participant and line at most once: one that couldn't make room
    // earlier in the search still can't, because a failed search changes nothing.
    var visitedParticipants: [Bool] = []
    var visitedLines: [Bool] = []
    func search(_ participant: Int) -> Bool {
      visitedParticipants[participant] = true
      let options = shareOptions[participant]
      while nextFree[participant] < options.count {
        let share = options[nextFree[participant]]
        nextFree[participant] += 1
        if !isRoundedUp[share], openUnits[shareLines[share]] > 0 {
          isRoundedUp[share] = true
          openUnits[shareLines[share]] -= 1
          return true
        }
      }
      for share in options
      where !isRoundedUp[share] && !visitedLines[shareLines[share]] {
        visitedLines[shareLines[share]] = true
        for other in lineShares[shareLines[share]]
        where isRoundedUp[other] && !visitedParticipants[sharers[other]] {
          isRoundedUp[other] = false
          if search(sharers[other]) {
            isRoundedUp[share] = true
            return true
          }
          isRoundedUp[other] = true
        }
      }
      return false
    }
    func roundUp(_ participant: Int) {
      visitedParticipants = Array(repeating: false, count: participantIDs.count)
      visitedLines = Array(repeating: false, count: lines.count)
      _ = search(participant)
    }

    var remainders: [(order: Int, isOwner: Bool, remainder: Double)] = []
    for (participant, id) in participantIDs.enumerated() where fractions[participant] > 0 {
      let fraction = snapped(fractions[participant])
      let wholeUnits = Int(fraction.rounded(.down))
      for _ in 0..<wholeUnits { roundUp(participant) }
      // Remainders within floating-point error of each other tie, so they keep their order.
      let remainder = ((fraction - Double(wholeUnits)) / tolerance).rounded() * tolerance
      remainders.append((participant, id == ownerID, remainder))
    }
    remainders.sort {
      ($0.isOwner ? 1 : 0, -$0.remainder, $0.order) < ($1.isOwner ? 1 : 0, -$1.remainder, $1.order)
    }
    for candidate in remainders where candidate.remainder > 0 { roundUp(candidate.order) }
    assert(openUnits.allSatisfy { $0 == 0 }, "Every line's units are placed")

    return lineShares.map { $0.map { floors[$0] + (isRoundedUp[$0] ? 1 : 0) } }
  }

  private static let tolerance = 1e-9

  /// `value`, or the whole number it's within floating-point error of.
  private static func snapped(_ value: Double) -> Double {
    let whole = value.rounded()
    return abs(value - whole) < tolerance ? whole : value
  }

  /// An amount in whole units and the fraction of it each participant sharing it owes.
  private struct Line {
    let units: Int
    let shares: [(id: ReceiptParticipant.ID, fraction: Double)]

    init(units: Int, weights: [Weight]) {
      let positiveWeights = weights.filter { $0.weight > 0 }
      let totalWeight = positiveWeights.reduce(0) { $0 + $1.weight }
      self.units = units
      shares = totalWeight > 0 ? positiveWeights.map { ($0.id, $0.weight / totalWeight) } : []
    }
  }

  private struct AdjustmentComponent {
    let id: String
    let title: String
    let units: Int
  }
}
