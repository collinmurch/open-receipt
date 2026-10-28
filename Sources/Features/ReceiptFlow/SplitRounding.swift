/// Rounds exact shares of whole units so every line and every participant comes out whole.
nonisolated enum SplitRounding {
  /// An amount in whole units and how heavily each participant sharing it is weighted. Each
  /// participant owes exactly `units * weight / totalWeight`.
  struct Line {
    let units: Int
    let shares: [(participant: Int, weight: Int128)]
    let totalWeight: Int128

    /// The largest total weight a line keeps, so exact shares of any amount fit in `Int128`. Weights
    /// past it, which only absurd amounts reach, are scaled down to it, close enough for rounding.
    private static let maximumTotalWeight: Int128 = 1 << 32

    /// A line split by `weights`, ignoring any that aren't positive, or `nil` when none is.
    init?(units: Int, weights: [(participant: Int, weight: Int128)]) {
      let positive = weights.filter { $0.weight > 0 }
      let divisor = positive.reduce(Int128(0)) { greatestCommonDivisor($0, $1.weight) }
      guard divisor > 0 else { return nil }
      var shares = positive.map { (participant: $0.participant, weight: $0.weight / divisor) }
      let total = shares.reduce(0) { $0 + $1.weight }
      if total > Self.maximumTotalWeight {
        let scale = (total - 1) / Self.maximumTotalWeight + 1
        shares = shares.map { ($0.participant, max(1, $0.weight / scale)) }
      }
      self.units = units
      self.shares = shares
      totalWeight = shares.reduce(0) { $0 + $1.weight }
    }

    /// The fraction of the line the share at `index` owes, for showing it.
    func fraction(at index: Int) -> Double {
      Double(shares[index].weight) / Double(totalWeight)
    }
  }

  /// The smallest number every line's total weight divides, over which every exact share's
  /// fraction of a unit is a whole number.
  static func commonDenominator(of lines: [Line]) -> Int128 {
    lines.reduce(1) { $0 / greatestCommonDivisor($0, $1.totalWeight) * $1.totalWeight }
  }

  /// Splits each line into whole units that add up to the line, rounding every exact share down or
  /// up so that each participant's total is also within one unit of their exact total.
  /// Participants furthest below their exact total are rounded up first, and `last` last, so they
  /// pay a leftover unit last and take a leftover saving first. The result holds each line's
  /// shares in order.
  ///
  /// Rounding a share up takes one of its line's leftover units. When a participant's lines have
  /// none left, someone already rounded up on one of them moves to another line of theirs that
  /// does, as in bipartite matching, so whether a participant can be rounded up never depends on
  /// the order lines were placed in.
  static func allocate(_ lines: [Line], participantCount: Int, last: Int?) -> [[Int]] {
    let denominator = commonDenominator(of: lines)
    // Every line's shares, numbered in one run, with whom each is for and its line.
    var lineShares: [Range<Int>] = []
    var sharers: [Int] = []
    var shareLines: [Int] = []
    var floors: [Int] = []
    var openUnits: [Int] = []
    // Each share's fraction of a unit above its floor, and each participant's in all, over
    // `denominator`.
    var options = Array(repeating: [(share: Int, fraction: Int128)](), count: participantCount)
    var fractions = Array(repeating: Int128(0), count: participantCount)
    for (lineIndex, line) in lines.enumerated() {
      let start = floors.count
      for share in line.shares {
        var (floor, remainder) = (Int128(line.units) * share.weight)
          .quotientAndRemainder(dividingBy: line.totalWeight)
        if remainder < 0 {
          floor -= 1
          remainder += line.totalWeight
        }
        if remainder > 0 {
          let fraction = remainder * (denominator / line.totalWeight)
          options[share.participant].append((floors.count, fraction))
          fractions[share.participant] += fraction
        }
        sharers.append(share.participant)
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
    var nextFree = Array(repeating: 0, count: participantCount)

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
      visitedParticipants = Array(repeating: false, count: participantCount)
      visitedLines = Array(repeating: false, count: lines.count)
      _ = search(participant)
    }

    var remainders: [(participant: Int, remainder: Int128)] = []
    for participant in 0..<participantCount where fractions[participant] > 0 {
      let (wholeUnits, remainder) = fractions[participant]
        .quotientAndRemainder(dividingBy: denominator)
      for _ in 0..<Int(wholeUnits) { roundUp(participant) }
      if remainder > 0 { remainders.append((participant, remainder)) }
    }
    remainders.sort {
      ($0.participant == last ? 1 : 0, -$0.remainder, $0.participant)
        < ($1.participant == last ? 1 : 0, -$1.remainder, $1.participant)
    }
    for candidate in remainders { roundUp(candidate.participant) }
    assert(openUnits.allSatisfy { $0 == 0 }, "Every line's units are placed")

    return lineShares.map { $0.map { floors[$0] + (isRoundedUp[$0] ? 1 : 0) } }
  }
}

private nonisolated func greatestCommonDivisor(_ a: Int128, _ b: Int128) -> Int128 {
  var (a, b) = (a.magnitude, b.magnitude)
  while b != 0 { (a, b) = (b, a % b) }
  return Int128(a)
}
