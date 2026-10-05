import SwiftUI

/// The shared motion of a receipt's backgrounds. Every page of a receipt reads the same motion,
/// so they always show the same frame. The wash drifts only while the receipt is being read and
/// otherwise rests, which lets its backgrounds stop redrawing.
@MainActor
@Observable
final class ReceiptBackgroundMotion {
  let pattern: ReceiptBackgroundMotionPattern
  /// Whether the wash is still. Resting backgrounds pause their timelines.
  private(set) var isResting: Bool
  @ObservationIgnored private var mode: Mode
  @ObservationIgnored private var settleTask: Task<Void, Never>?

  private enum Mode {
    case resting
    case drifting(origin: Date)
    case settling(from: Float, start: Date)
  }

  static let driftPeriod: TimeInterval = 18
  static let settleDuration: TimeInterval = 1.6

  /// Creates motion whose wash layout derives from `seed`, so a receipt looks the same each time
  /// it opens.
  init(seed: UUID = UUID(), isDrifting: Bool = false, now: Date = .now) {
    pattern = ReceiptBackgroundMotionPattern(seed: seed)
    mode = isDrifting ? .drifting(origin: now) : .resting
    isResting = !isDrifting
  }

  func phase(at date: Date) -> Float {
    switch mode {
    case .resting:
      return 0
    case .drifting(let origin):
      let elapsed = date.timeIntervalSince(origin)
      return Float(sin(elapsed / Self.driftPeriod * 2 * .pi))
    case .settling(let from, let start):
      let progress = min(1, max(0, date.timeIntervalSince(start) / Self.settleDuration))
      let eased = progress * progress * (3 - 2 * progress)
      return from * Float(1 - eased)
    }
  }

  /// Starts drifting from the current frame.
  func drift(now: Date = .now) {
    if case .drifting = mode { return }
    settleTask?.cancel()
    let current = Double(max(-1, min(1, phase(at: now))))
    let offset = asin(current) / (2 * .pi) * Self.driftPeriod
    mode = .drifting(origin: now.addingTimeInterval(-offset))
    isResting = false
  }

  /// Eases from the current frame to the resting frame, then stops redrawing.
  func settle(now: Date = .now) {
    guard case .drifting = mode else { return }
    mode = .settling(from: phase(at: now), start: now)
    settleTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.settleDuration))
      guard !Task.isCancelled else { return }
      self?.rest()
    }
  }

  func rest() {
    settleTask?.cancel()
    mode = .resting
    isResting = true
  }
}

extension EnvironmentValues {
  /// The motion every background of the open receipt shares.
  @Entry var receiptBackgroundMotion: ReceiptBackgroundMotion? = nil
}

/// Where the wash's two blooms travel as it drifts, laid out from a seed.
struct ReceiptBackgroundMotionPattern: Sendable {
  let leadingStart: UnitPoint
  let leadingEnd: UnitPoint
  let trailingStart: UnitPoint
  let trailingEnd: UnitPoint

  init(seed: UUID) {
    var generator = SeededRandomNumberGenerator(seed: seed)
    leadingStart = UnitPoint(
      x: Double.random(in: -0.08...0.2, using: &generator),
      y: Double.random(in: 0.08...0.48, using: &generator))
    leadingEnd = UnitPoint(
      x: Double.random(in: 0.18...0.52, using: &generator),
      y: Double.random(in: 0.5...0.9, using: &generator))
    trailingStart = UnitPoint(
      x: Double.random(in: 0.78...1.08, using: &generator),
      y: Double.random(in: 0.52...0.92, using: &generator))
    trailingEnd = UnitPoint(
      x: Double.random(in: 0.48...0.82, using: &generator),
      y: Double.random(in: 0.1...0.5, using: &generator))
  }

  func leadingCenter(at progress: Double) -> UnitPoint {
    interpolatedPoint(from: leadingStart, to: leadingEnd, progress: progress)
  }

  func trailingCenter(at progress: Double) -> UnitPoint {
    interpolatedPoint(from: trailingStart, to: trailingEnd, progress: progress)
  }

  private func interpolatedPoint(
    from start: UnitPoint,
    to end: UnitPoint,
    progress: Double
  ) -> UnitPoint {
    UnitPoint(
      x: start.x + (end.x - start.x) * progress,
      y: start.y + (end.y - start.y) * progress)
  }
}

/// A SplitMix64 generator, so a seed always produces the same wash layout.
private struct SeededRandomNumberGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UUID) {
    state = withUnsafeBytes(of: seed.uuid) { bytes in
      bytes.loadUnaligned(as: UInt64.self)
        ^ bytes.loadUnaligned(fromByteOffset: 8, as: UInt64.self)
    }
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
