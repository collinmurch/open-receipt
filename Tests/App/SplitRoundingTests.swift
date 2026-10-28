import XCTest

@testable import open_receipt

final class SplitRoundingTests: XCTestCase {
  func testLineSharesAddUpToLine() throws {
    let line = try XCTUnwrap(evenLine(units: 100, count: 3))

    let allocation = SplitRounding.allocate([line], participantCount: 3, last: nil)

    XCTAssertEqual(allocation, [[34, 33, 33]])
  }

  func testLastParticipantPaysLeftoverUnitLast() throws {
    let line = try XCTUnwrap(evenLine(units: 100, count: 3))

    let allocation = SplitRounding.allocate([line], participantCount: 3, last: 0)

    XCTAssertEqual(allocation, [[33, 34, 33]])
  }

  func testLastParticipantTakesLeftoverSavingFirst() throws {
    let line = try XCTUnwrap(evenLine(units: -100, count: 3))

    let allocation = SplitRounding.allocate([line], participantCount: 3, last: 0)

    XCTAssertEqual(allocation, [[-34, -33, -33]])
  }

  func testLineReducesWeightsToLowestTerms() throws {
    let line = try XCTUnwrap(SplitRounding.Line(units: 9, weights: [(0, 20), (1, 40)]))

    XCTAssertEqual(line.shares.map(\.weight), [1, 2])
    XCTAssertEqual(line.totalWeight, 3)
  }

  func testLineWithoutPositiveWeightsIsNil() {
    XCTAssertNil(SplitRounding.Line(units: 9, weights: [(0, 0), (1, -2)]))
  }

  func testLargeAmountsSplitExactly() throws {
    let weights = (0..<20).map { (participant: $0, weight: Int128(1_000_003 + $0 * 7_919)) }
    let line = try XCTUnwrap(SplitRounding.Line(units: 999_999_999_999, weights: weights))

    let allocation = SplitRounding.allocate([line], participantCount: 20, last: nil)

    XCTAssertEqual(allocation[0].reduce(0, +), 999_999_999_999)
  }

  func testHugeWeightsOnHugeAmountsSplitWithoutOverflow() throws {
    let weights = (0..<40).map { (participant: $0, weight: Int128(Int.max) * Int128($0 + 1)) }
    let line = try XCTUnwrap(SplitRounding.Line(units: Int.max / 2, weights: weights))

    let allocation = SplitRounding.allocate([line], participantCount: 40, last: nil)

    XCTAssertEqual(allocation[0].reduce(0, +), Int.max / 2)
  }

  func testScalingKeepsEveryPositiveWeight() throws {
    let weights = [(participant: 0, weight: Int128(1) << 80), (participant: 1, weight: Int128(1))]
    let line = try XCTUnwrap(SplitRounding.Line(units: 10, weights: weights))

    XCTAssertEqual(line.shares.count, 2)
    XCTAssertGreaterThan(line.shares[1].weight, 0)
  }

  private func evenLine(units: Int, count: Int) -> SplitRounding.Line? {
    SplitRounding.Line(units: units, weights: (0..<count).map { ($0, 1) })
  }
}
