import XCTest

@testable import open_receipt

final class ReceiptBackgroundMotionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 1_000)

  func testStartsFromRestingFrame() {
    let motion = ReceiptBackgroundMotion(origin: start)

    XCTAssertEqual(motion.phase(at: start), 0, accuracy: 0.0001)
  }

  func testDriftsAfterStarting() {
    let motion = ReceiptBackgroundMotion(origin: start)

    XCTAssertNotEqual(motion.phase(at: start.addingTimeInterval(2)), 0)
  }

  func testRepeatsEachPeriod() {
    let motion = ReceiptBackgroundMotion(origin: start)
    let date = start.addingTimeInterval(5)

    XCTAssertEqual(
      motion.phase(at: date),
      motion.phase(at: date.addingTimeInterval(ReceiptBackgroundMotion.period)),
      accuracy: 0.0001)
  }

  func testSameSeedLaysOutTheSameWash() {
    let seed = UUID()
    let first = ReceiptBackgroundMotion(seed: seed).pattern
    let second = ReceiptBackgroundMotion(seed: seed).pattern

    XCTAssertEqual(first.leadingStart, second.leadingStart)
    XCTAssertEqual(first.trailingEnd, second.trailingEnd)
  }
}
