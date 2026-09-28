#if !SWIFT_PACKAGE
  import XCTest
  @testable import open_receipt

  @MainActor
  final class ReceiptBackgroundMotionTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func testRestingMotionShowsRestingFrame() {
      let motion = ReceiptBackgroundMotion()

      XCTAssertTrue(motion.isResting)
      XCTAssertEqual(motion.phase(at: start), 0)
    }

    func testDriftingMotionMoves() {
      let motion = ReceiptBackgroundMotion(isDrifting: true, now: start)

      XCTAssertFalse(motion.isResting)
      XCTAssertNotEqual(motion.phase(at: start.addingTimeInterval(2)), 0)
    }

    func testDriftStartsFromRestingFrame() {
      let motion = ReceiptBackgroundMotion()

      motion.drift(now: start)

      XCTAssertEqual(motion.phase(at: start), 0, accuracy: 0.0001)
      XCTAssertFalse(motion.isResting)
    }

    func testSettleContinuesFromCurrentFrame() {
      let motion = ReceiptBackgroundMotion(isDrifting: true, now: start)
      let settleTime = start.addingTimeInterval(3)
      let frameBeforeSettling = motion.phase(at: settleTime)

      motion.settle(now: settleTime)

      XCTAssertEqual(motion.phase(at: settleTime), frameBeforeSettling, accuracy: 0.0001)
    }

    func testSettleEndsOnRestingFrame() {
      let motion = ReceiptBackgroundMotion(isDrifting: true, now: start)
      let settleTime = start.addingTimeInterval(3)

      motion.settle(now: settleTime)

      let end = settleTime.addingTimeInterval(ReceiptBackgroundMotion.settleDuration)
      XCTAssertEqual(motion.phase(at: end), 0, accuracy: 0.0001)
    }

    func testRestStopsRedrawing() {
      let motion = ReceiptBackgroundMotion(isDrifting: true, now: start)

      motion.rest()

      XCTAssertTrue(motion.isResting)
      XCTAssertEqual(motion.phase(at: start.addingTimeInterval(5)), 0)
    }

    func testSettlingRestingMotionDoesNothing() {
      let motion = ReceiptBackgroundMotion()

      motion.settle(now: start)

      XCTAssertTrue(motion.isResting)
    }
  }
#endif
