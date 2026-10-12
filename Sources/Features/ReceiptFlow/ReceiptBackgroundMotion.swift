import SwiftUI

/// The shared motion of a receipt's backgrounds. The wash drifts on a fixed cycle measured from
/// `origin`, so every page that reads the same motion draws the same frame at the same moment and
/// moving between pages never jumps.
struct ReceiptBackgroundMotion: Sendable {
  let pattern: ReceiptBackgroundMotionPattern
  let origin: Date

  static let period: TimeInterval = 18

  /// Motion for backgrounds outside a receipt, which have no shared motion of their own.
  static let standalone = ReceiptBackgroundMotion()

  /// Creates motion whose wash layout derives from `seed`, so a receipt looks the same each time
  /// it opens. The wash starts from its resting frame at `origin`.
  init(seed: UUID = UUID(), origin: Date = .now) {
    pattern = ReceiptBackgroundMotionPattern(seed: seed)
    self.origin = origin
  }

  func phase(at date: Date) -> Float {
    Float(sin(date.timeIntervalSince(origin) / Self.period * 2 * .pi))
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
