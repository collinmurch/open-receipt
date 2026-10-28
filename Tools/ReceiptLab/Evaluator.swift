import Foundation
import ReceiptKit

struct FixtureEvaluation: Encodable {
  let passed: Bool
  let checks: [Check]

  struct Check: Encodable {
    enum Status: String, Encodable { case pass, fail, skipped }
    let field: String
    let status: Status
    let expected: String?
    let actual: String?
    let detail: String?
  }
}

enum FixtureEvaluator {
  private static let minimumDescriptionSimilarity = 0.60

  static func evaluate(actual: ParsedReceipt, expected: ExpectedReceipt) -> FixtureEvaluation {
    let tolerance = expected.amountTolerance ?? 0.01
    var checks: [FixtureEvaluation.Check] = []

    if let expectedCurrency = expected.currency {
      let pass = expectedCurrency.uppercased() == actual.currency.uppercased()
      checks.append(
        FixtureEvaluation.Check(
          field: "currency",
          status: pass ? .pass : .fail,
          expected: expectedCurrency.uppercased(),
          actual: actual.currency,
          detail: nil))
    }

    let amounts: [(String, KeyPath<ExpectedReceipt, Double?>, KeyPath<ParsedReceipt, Money>)] = [
      ("subtotal", \.subtotal, \.subtotal), ("tax", \.tax, \.tax), ("tip", \.tip, \.tip),
      ("savings", \.savings, \.savings), ("total", \.total, \.total),
    ]
    for (field, expectedAmount, actualAmount) in amounts {
      checks.append(
        amountCheck(
          field: field, expected: expected[keyPath: expectedAmount],
          actual: Double(actual[keyPath: actualAmount]), tolerance: tolerance))
    }
    checks.append(
      itemCountCheck(expected: expected.itemCount, actual: actual.items.count))
    if let expectedItems = expected.items {
      let matches = matchItems(
        expected: expectedItems,
        actual: actual.items,
        tolerance: tolerance)
      checks.append(
        itemAmountSummaryCheck(
          expected: expectedItems,
          actual: actual.items,
          matches: matches))
      checks.append(
        contentsOf: itemChecks(
          expected: expectedItems,
          actual: actual.items,
          matches: matches,
          tolerance: tolerance))
    } else {
      checks.append(
        FixtureEvaluation.Check(
          field: "itemAmounts",
          status: .skipped,
          expected: nil,
          actual: "\(actual.items.count) parsed",
          detail: nil))
    }

    let activeChecks = checks.filter { $0.status != .skipped }
    let passed = activeChecks.allSatisfy { $0.status == .pass }
    return FixtureEvaluation(passed: passed, checks: checks)
  }

  private static func amountCheck(
    field: String,
    expected: Double?,
    actual: Double,
    tolerance: Double
  ) -> FixtureEvaluation.Check {
    guard let expected else {
      return FixtureEvaluation.Check(
        field: field, status: .skipped, expected: nil, actual: format(actual), detail: nil)
    }
    let diff = abs(expected - actual)
    return FixtureEvaluation.Check(
      field: field,
      status: diff <= tolerance ? .pass : .fail,
      expected: format(expected),
      actual: format(actual),
      detail: diff <= tolerance ? nil : String(format: "Δ %.2f", diff))
  }

  private static func itemCountCheck(expected: Int?, actual: Int) -> FixtureEvaluation.Check {
    guard let expected else {
      return FixtureEvaluation.Check(
        field: "itemCount", status: .skipped, expected: nil, actual: String(actual), detail: nil)
    }
    let delta = actual - expected
    return FixtureEvaluation.Check(
      field: "itemCount",
      status: delta == 0 ? .pass : .fail,
      expected: String(expected),
      actual: String(actual),
      detail: delta == 0 ? nil : "Δ \(delta)")
  }

  private static func itemChecks(
    expected: [ExpectedItem],
    actual: [ReceiptItem],
    matches: ItemMatches,
    tolerance: Double
  ) -> [FixtureEvaluation.Check] {
    var checks: [FixtureEvaluation.Check] = []

    for (index, item) in expected.enumerated() {
      if let match = matches.byExpectedIndex[index] {
        let actualItem = actual[match.index]
        checks.append(
          nameCheck(
            index: index,
            expected: item.rawName,
            actual: actualItem.description,
            similarity: match.similarity))
        if let quantity = item.quantity {
          checks.append(
            amountCheck(
              field: "items[\(index)].quantity",
              expected: quantity,
              actual: actualItem.quantity,
              tolerance: 0.001))
        }
        if let unitPrice = item.unitPrice {
          checks.append(
            unitPriceCheck(
              index: index,
              expected: unitPrice,
              actual: actualItem,
              tolerance: tolerance))
        }
      } else {
        checks.append(
          FixtureEvaluation.Check(
            field: "items[\(index)]",
            status: .fail,
            expected: "\(item.rawName) \(format(item.lineTotal))",
            actual: nil,
            detail: "missing expected item"))
      }
    }

    for index in actual.indices where !matches.usedActual.contains(index) {
      let item = actual[index]
      checks.append(
        FixtureEvaluation.Check(
          field: "items.extra[\(index)]",
          status: .fail,
          expected: nil,
          actual: "\(item.description) \(format(Double(item.lineTotal)))",
          detail: "unexpected parsed item"))
    }
    return checks
  }

  private static func itemAmountSummaryCheck(
    expected: [ExpectedItem],
    actual: [ReceiptItem],
    matches: ItemMatches
  ) -> FixtureEvaluation.Check {
    let matched = matches.byExpectedIndex.count
    let missing = expected.count - matched
    let extra = actual.count - matches.usedActual.count
    let pass = missing == 0 && extra == 0
    let recall = expected.isEmpty ? 1 : Double(matched) / Double(expected.count)
    let precision = actual.isEmpty ? 1 : Double(matches.usedActual.count) / Double(actual.count)
    return FixtureEvaluation.Check(
      field: "itemAmounts",
      status: pass ? .pass : .fail,
      expected: "\(expected.count) expected, 0 extra",
      actual: "\(matched) matched, \(missing) missing, \(extra) extra",
      detail: String(
        format: "recall %.0f%%, precision %.0f%%",
        recall * 100,
        precision * 100))
  }

  private struct ItemMatches {
    /// The parsed item each expected item matched, by the expected item's index.
    let byExpectedIndex: [Int: (index: Int, similarity: Double)]
    let usedActual: Set<Int>
  }

  private static func matchItems(
    expected: [ExpectedItem],
    actual: [ReceiptItem],
    tolerance: Double
  ) -> ItemMatches {
    var byExpectedIndex: [Int: (index: Int, similarity: Double)] = [:]
    var usedActual: Set<Int> = []
    for (expectedIndex, item) in expected.enumerated() {
      guard
        let match = bestMatch(
          for: item,
          actual: actual,
          usedActual: usedActual,
          tolerance: tolerance)
      else { continue }
      byExpectedIndex[expectedIndex] = match
      usedActual.insert(match.index)
    }
    return ItemMatches(byExpectedIndex: byExpectedIndex, usedActual: usedActual)
  }

  private static func bestMatch(
    for expected: ExpectedItem,
    actual: [ReceiptItem],
    usedActual: Set<Int>,
    tolerance: Double
  ) -> (index: Int, similarity: Double)? {
    actual.indices
      .filter { !usedActual.contains($0) }
      .compactMap { index -> (Int, Double)? in
        let item = actual[index]
        guard abs(Double(item.lineTotal) - expected.lineTotal) <= tolerance else { return nil }
        let nameSimilarity = descriptionSimilarity(expected.rawName, item.description)
        return (index, nameSimilarity)
      }
      .max { $0.1 < $1.1 }
  }

  private static func nameCheck(
    index: Int,
    expected: String,
    actual: String,
    similarity: Double
  ) -> FixtureEvaluation.Check {
    let pass = similarity >= minimumDescriptionSimilarity
    return FixtureEvaluation.Check(
      field: "items[\(index)].name",
      status: pass ? .pass : .fail,
      expected: expected,
      actual: actual,
      detail: String(format: "similarity %.0f%%", similarity * 100))
  }

  private static func unitPriceCheck(
    index: Int,
    expected: Double,
    actual: ReceiptItem,
    tolerance: Double
  ) -> FixtureEvaluation.Check {
    guard actual.quantity.isFinite, actual.quantity != 0 else {
      return FixtureEvaluation.Check(
        field: "items[\(index)].unitPrice",
        status: .fail,
        expected: format(expected),
        actual: nil,
        detail: "cannot derive from parsed quantity and line total")
    }
    return amountCheck(
      field: "items[\(index)].unitPrice",
      expected: expected,
      actual: Double(actual.lineTotal) / actual.quantity,
      tolerance: tolerance)
  }

  private static func descriptionSimilarity(_ expected: String, _ actual: String) -> Double {
    let expectedTokens = Set(tokens(expected))
    guard !expectedTokens.isEmpty else { return 1 }
    let actualTokens = Set(tokens(actual))
    let matched = expectedTokens.intersection(actualTokens).count
    let tokenDice =
      actualTokens.isEmpty
      ? 0
      : Double(2 * matched) / Double(expectedTokens.count + actualTokens.count)
    let expectedText = expectedTokens.sorted().joined()
    let actualText = actualTokens.sorted().joined()
    let characterSimilarity = normalizedCharacterSimilarity(expectedText, actualText)
    return max(tokenDice, characterSimilarity)
  }

  private static func tokens(_ text: String) -> [String] {
    text.uppercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { token in
        token.count >= 2 && token.contains(where: \.isLetter)
      }
  }

  private static func normalizedCharacterSimilarity(_ lhs: String, _ rhs: String) -> Double {
    guard !lhs.isEmpty else { return rhs.isEmpty ? 1 : 0 }
    guard !rhs.isEmpty else { return 0 }
    let lhs = Array(lhs)
    let rhs = Array(rhs)
    var previous = Array(0...rhs.count)
    for (leftIndex, left) in lhs.enumerated() {
      var current = [leftIndex + 1]
      for (rightIndex, right) in rhs.enumerated() {
        current.append(
          min(
            current[rightIndex] + 1,
            previous[rightIndex + 1] + 1,
            previous[rightIndex] + (left == right ? 0 : 1)))
      }
      previous = current
    }
    let distance = previous[rhs.count]
    return 1 - Double(distance) / Double(max(lhs.count, rhs.count))
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.2f", value)
  }
}
