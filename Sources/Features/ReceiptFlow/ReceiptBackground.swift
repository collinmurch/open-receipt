import Foundation
import Observation
import SwiftUI

/// The shared motion of a receipt's backgrounds. Every page of a receipt reads the same motion,
/// so they always show the same frame. The wash drifts only while the receipt is being read and
/// otherwise rests, which lets its backgrounds stop redrawing.
@Observable
final class ReceiptBackgroundMotion: @unchecked Sendable {
  fileprivate let pattern: ReceiptBackgroundMotionPattern
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
  @MainActor
  func drift(now: Date = .now) {
    if case .drifting = mode { return }
    settleTask?.cancel()
    let current = Double(max(-1, min(1, phase(at: now))))
    let offset = asin(current) / (2 * .pi) * Self.driftPeriod
    mode = .drifting(origin: now.addingTimeInterval(-offset))
    isResting = false
  }

  /// Eases from the current frame to the resting frame, then stops redrawing.
  @MainActor
  func settle(now: Date = .now) {
    guard case .drifting = mode else { return }
    mode = .settling(from: phase(at: now), start: now)
    settleTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(Self.settleDuration))
      guard !Task.isCancelled, let self else { return }
      self.rest()
    }
  }

  @MainActor
  func rest() {
    settleTask?.cancel()
    mode = .resting
    isResting = true
  }
}

private struct ReceiptBackgroundMotionKey: EnvironmentKey {
  static let defaultValue = ReceiptBackgroundMotion()
}

extension EnvironmentValues {
  var receiptBackgroundMotion: ReceiptBackgroundMotion {
    get { self[ReceiptBackgroundMotionKey.self] }
    set { self[ReceiptBackgroundMotionKey.self] = newValue }
  }
}

extension View {
  func receiptBackground(_ style: ReceiptBackgroundStyle) -> some View {
    scrollContentBackground(.hidden)
      .background {
        ReceiptInkWashBackground(style: style)
      }
  }
}

struct ReceiptInkWashBackground: View {
  let style: ReceiptBackgroundStyle
  @State private var isVisible = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.receiptBackgroundMotion) private var motion
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let palette = style.inkWashPalette(for: colorScheme)

    ZStack {
      palette.base

      TimelineView(
        .animation(
          minimumInterval: 1 / 30,
          paused: reduceMotion || !isVisible || motion.isResting)
      ) { context in
        animatedFields(
          palette: palette,
          phase: reduceMotion ? 0 : motion.phase(at: context.date))
      }

      LinearGradient(
        colors: [.clear, .black.opacity(colorScheme == .dark ? 0.1 : 0.04)],
        startPoint: UnitPoint(x: 0.5, y: 0.48),
        endPoint: .bottom)

      ReceiptBackgroundGrain(seed: style.grainSeed)
        .blendMode(.softLight)
    }
    // One flattened layer: scrolling content and glass above it composite a single texture
    // instead of blending seven full-screen layers every frame.
    .drawingGroup()
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .onAppear { isVisible = true }
    .onDisappear { isVisible = false }
  }

  private func animatedFields(
    palette: ReceiptInkWashPalette,
    phase: Float
  ) -> some View {
    let leadingDominance = (Double(phase) + 1) / 2
    let trailingDominance = 1 - leadingDominance
    let highlightOpacity =
      colorScheme == .dark
      ? 0.22 + Double(phase) * 0.08
      : 0.44
        + Double(phase) * 0.1
    let bloomOpacity =
      colorScheme == .dark
      ? 0.19 - Double(phase) * 0.07
      : 0.32
        - Double(phase) * 0.08

    return ZStack {
      MeshGradient(
        width: 3,
        height: 3,
        points: [
          SIMD2<Float>(0, 0), SIMD2<Float>(0.54, 0), SIMD2<Float>(1, 0),
          SIMD2<Float>(0, 0.48),
          SIMD2<Float>(0.58 + phase * 0.07, 0.4 + phase * 0.05),
          SIMD2<Float>(1, 0.55),
          SIMD2<Float>(0, 1), SIMD2<Float>(0.42, 1), SIMD2<Float>(1, 1),
        ],
        colors: palette.meshColors,
        background: palette.base,
        smoothsColors: true)

      RadialGradient(
        colors: [
          palette.leadingWash.opacity(0.12 + leadingDominance * 0.44),
          palette.leadingWash.opacity(leadingDominance * 0.24),
          .clear,
        ],
        center: motion.pattern.leadingCenter(at: leadingDominance),
        startRadius: 20,
        endRadius: 900)

      RadialGradient(
        colors: [
          palette.trailingWash.opacity(0.12 + trailingDominance * 0.44),
          palette.trailingWash.opacity(trailingDominance * 0.24),
          .clear,
        ],
        center: motion.pattern.trailingCenter(at: leadingDominance),
        startRadius: 20,
        endRadius: 900)

      RadialGradient(
        colors: [palette.highlight.opacity(highlightOpacity), .clear],
        center: UnitPoint(
          x: 0.92 + Double(phase) * 0.07,
          y: 0.04 + Double(phase) * 0.03),
        startRadius: 10,
        endRadius: 430)

      RadialGradient(
        colors: [palette.bloom.opacity(bloomOpacity), .clear],
        center: UnitPoint(
          x: 0.08 + Double(phase) * 0.07,
          y: 0.42 - Double(phase) * 0.06),
        startRadius: 0,
        endRadius: 360)
    }
  }
}

private struct ReceiptBackgroundMotionPattern: Sendable {
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

private struct ReceiptBackgroundGrain: View {
  let seed: UInt64
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Image(uiImage: ReceiptBackgroundGrainCache.image(seed: seed, colorScheme: colorScheme))
      .resizable(resizingMode: .tile)
      .interpolation(.none)
  }
}

@MainActor
private enum ReceiptBackgroundGrainCache {
  private static let tileSize = CGSize(width: 320, height: 320)
  private static let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = ReceiptThemeColor.allCases.count * 2
    return cache
  }()

  static func image(seed: UInt64, colorScheme: ColorScheme) -> UIImage {
    let isDark = colorScheme == .dark
    let key = "\(seed)-\(isDark)" as NSString
    if let image = cache.object(forKey: key) {
      return image
    }

    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: tileSize, format: format).image { renderer in
      let context = renderer.cgContext
      let grainColor = isDark ? UIColor.white : UIColor.black
      var randomState = seed
      let count = max(900, Int(tileSize.width * tileSize.height / 92))

      for index in 0..<count {
        let x = nextUnitValue(state: &randomState) * tileSize.width
        let y = nextUnitValue(state: &randomState) * tileSize.height
        let grainSize = 0.35 + nextUnitValue(state: &randomState) * 0.75
        let rect = CGRect(x: x, y: y, width: grainSize, height: grainSize)
        context.setFillColor(
          grainColor.withAlphaComponent(index.isMultiple(of: 5) ? 0.12 : 0.075).cgColor)
        if index.isMultiple(of: 5) {
          context.fillEllipse(in: rect)
        } else {
          context.fill(rect)
        }
      }
    }
    cache.setObject(image, forKey: key)
    return image
  }

  private static func nextUnitValue(state: inout UInt64) -> CGFloat {
    state = 2_862_933_555_777_941_757 &* state &+ 3_037_000_493
    return CGFloat(state & 0x00FF_FFFF) / CGFloat(0x0100_0000)
  }
}

private struct ReceiptInkWashPalette {
  let base: Color
  let meshColors: [Color]
  let highlight: Color
  let bloom: Color

  var leadingWash: Color {
    meshColors.first ?? base
  }

  var trailingWash: Color {
    meshColors.last ?? base
  }
}

extension ReceiptBackgroundStyle {
  func accentColor(for colorScheme: ColorScheme) -> Color {
    primary.accentColor(for: colorScheme)
  }

  func colors(for colorScheme: ColorScheme) -> [Color] {
    [primary.backgroundColor(for: colorScheme), secondary.backgroundColor(for: colorScheme)]
  }

  fileprivate func inkWashPalette(for colorScheme: ColorScheme) -> ReceiptInkWashPalette {
    let base =
      colorScheme == .dark
      ? Color(red: 0.035, green: 0.04, blue: 0.05)
      : Color(red: 0.95, green: 0.95, blue: 0.94)
    let primaryColor = primary.backgroundColor(for: colorScheme)
    let secondaryColor = secondary.backgroundColor(for: colorScheme)

    return ReceiptInkWashPalette(
      base: base,
      meshColors: [
        primaryColor, base, secondaryColor,
        primaryColor, base, secondaryColor,
        primaryColor, secondaryColor, secondaryColor,
      ],
      highlight: primary.accentColor(for: colorScheme),
      bloom: secondary.accentColor(for: colorScheme))
  }

  fileprivate var grainSeed: UInt64 {
    UInt64(primary.paletteIndex + 1) * 1_592_746
      + UInt64(secondary.paletteIndex + 1) * 2_803_917
  }
}

extension ReceiptThemeColor {
  fileprivate func accentColor(for colorScheme: ColorScheme) -> Color {
    switch (self, colorScheme) {
    case (.blue, .light): Color(red: 0.05, green: 0.42, blue: 0.82)
    case (.blue, .dark): Color(red: 0.22, green: 0.72, blue: 1)
    case (.mint, .light): Color(red: 0, green: 0.48, blue: 0.36)
    case (.mint, .dark): Color(red: 0.24, green: 0.86, blue: 0.68)
    case (.peach, .light): Color(red: 0.82, green: 0.30, blue: 0.22)
    case (.peach, .dark): Color(red: 1, green: 0.56, blue: 0.36)
    case (.violet, .light): Color(red: 0.48, green: 0.30, blue: 0.78)
    case (.violet, .dark): Color(red: 0.68, green: 0.56, blue: 1)
    case (.amber, .light): Color(red: 0.72, green: 0.43, blue: 0.02)
    case (.amber, .dark): Color(red: 1, green: 0.72, blue: 0.2)
    case (.rose, .light): Color(red: 0.76, green: 0.18, blue: 0.38)
    case (.rose, .dark): Color(red: 1, green: 0.4, blue: 0.62)
    case (.forest, .light): Color(red: 0.12, green: 0.43, blue: 0.18)
    case (.forest, .dark): Color(red: 0.4, green: 0.82, blue: 0.42)
    case (.indigo, .light): Color(red: 0.25, green: 0.28, blue: 0.74)
    case (.indigo, .dark): Color(red: 0.48, green: 0.58, blue: 1)
    @unknown default: .accentColor
    }
  }

  fileprivate func backgroundColor(for colorScheme: ColorScheme) -> Color {
    switch (self, colorScheme) {
    case (.blue, .light): Color(red: 0.78, green: 0.9, blue: 1)
    case (.blue, .dark): Color(red: 0.05, green: 0.13, blue: 0.28)
    case (.mint, .light): Color(red: 0.76, green: 0.96, blue: 0.87)
    case (.mint, .dark): Color(red: 0.03, green: 0.22, blue: 0.16)
    case (.peach, .light): Color(red: 1, green: 0.82, blue: 0.7)
    case (.peach, .dark): Color(red: 0.32, green: 0.12, blue: 0.06)
    case (.violet, .light): Color(red: 0.85, green: 0.79, blue: 1)
    case (.violet, .dark): Color(red: 0.18, green: 0.08, blue: 0.32)
    case (.amber, .light): Color(red: 1, green: 0.9, blue: 0.58)
    case (.amber, .dark): Color(red: 0.3, green: 0.2, blue: 0.03)
    case (.rose, .light): Color(red: 1, green: 0.76, blue: 0.84)
    case (.rose, .dark): Color(red: 0.3, green: 0.07, blue: 0.14)
    case (.forest, .light): Color(red: 0.74, green: 0.91, blue: 0.72)
    case (.forest, .dark): Color(red: 0.04, green: 0.18, blue: 0.08)
    case (.indigo, .light): Color(red: 0.78, green: 0.82, blue: 1)
    case (.indigo, .dark): Color(red: 0.08, green: 0.09, blue: 0.3)
    @unknown default: Color(.secondarySystemGroupedBackground)
    }
  }

  fileprivate var paletteIndex: Int {
    ReceiptThemeColor.allCases.firstIndex(of: self) ?? 0
  }
}
