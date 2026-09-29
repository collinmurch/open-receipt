import Combine
import Foundation
import Observation
import SwiftUI

/// The shared motion of a receipt's backgrounds. Every page of a receipt reads the same motion,
/// so they always show the same frame. The wash drifts only while the receipt is being read and
/// otherwise rests, which lets its backgrounds stop redrawing.
@MainActor
@Observable
final class ReceiptBackgroundMotion {
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

extension View {
  /// Spacing for a bar pinned above a receipt's list, shared so the reading and review screens
  /// line up their rows.
  func receiptTopBarPadding() -> some View {
    padding(.horizontal).padding(.vertical, 8)
  }

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
  @State private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
  /// Resting motion for a background shown outside a receipt, which has no shared motion.
  @State private var restingMotion = ReceiptBackgroundMotion()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.receiptBackgroundMotion) private var sharedMotion
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let motion = sharedMotion ?? restingMotion
    let palette = style.inkWashPalette(for: colorScheme)
    let pattern = motion.pattern
    let isDark = colorScheme == .dark

    TimelineView(
      .animation(
        minimumInterval: 1 / 30,
        paused: reduceMotion || isLowPowerModeEnabled || !isVisible || motion.isResting)
    ) { context in
      let phase = reduceMotion ? 0 : motion.phase(at: context.date)
      Rectangle()
        .visualEffect { content, proxy in
          content.colorEffect(
            ReceiptInkWashShader.shader(
              size: proxy.size, palette: palette, pattern: pattern, phase: phase, isDark: isDark))
        }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .onAppear { isVisible = true }
    .onDisappear { isVisible = false }
    .onReceive(
      NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
        .receive(on: DispatchQueue.main)
    ) { _ in
      isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
  }
}

private enum ReceiptInkWashShader {
  static func shader(
    size: CGSize,
    palette: ReceiptInkWashPalette,
    pattern: ReceiptBackgroundMotionPattern,
    phase: Float,
    isDark: Bool
  ) -> Shader {
    let phase = Double(phase)
    let leadingDominance = (phase + 1) / 2
    let trailingDominance = 1 - leadingDominance
    let highlightOpacity = isDark ? 0.22 + phase * 0.08 : 0.44 + phase * 0.1
    let bloomOpacity = isDark ? 0.19 - phase * 0.07 : 0.32 - phase * 0.08
    let leadingCenter = pattern.leadingCenter(at: leadingDominance)
    let trailingCenter = pattern.trailingCenter(at: leadingDominance)

    return ShaderLibrary.receiptInkWash(
      .float2(size),
      .color(palette.base),
      .color(palette.primary),
      .color(palette.secondary),
      .color(palette.highlight),
      .color(palette.bloom),
      .float2(0.58 + phase * 0.07, 0.4 + phase * 0.05),
      .float2(leadingCenter.x, leadingCenter.y),
      .float2(trailingCenter.x, trailingCenter.y),
      .float4(
        0.12 + leadingDominance * 0.44,
        leadingDominance * 0.24,
        0.12 + trailingDominance * 0.44,
        trailingDominance * 0.24),
      .float2(0.92 + phase * 0.07, 0.04 + phase * 0.03),
      .float2(0.08 + phase * 0.07, 0.42 - phase * 0.06),
      .float2(highlightOpacity, bloomOpacity),
      .float(isDark ? 0.1 : 0.04),
      .float(isDark ? 1 : 0),
      .float(palette.grainSeed))
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

private struct ReceiptInkWashPalette {
  let base: Color
  let primary: Color
  let secondary: Color
  let highlight: Color
  let bloom: Color
  let grainSeed: Float
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
      primary: primaryColor,
      secondary: secondaryColor,
      highlight: primary.accentColor(for: colorScheme),
      bloom: secondary.accentColor(for: colorScheme),
      grainSeed: Float(primary.paletteIndex * 8 + secondary.paletteIndex) * 7.31)
  }

  /// A darker accent that stays legible under white labels, for prominent tinted controls.
  var prominentColor: Color {
    primary.accentColor(for: .light)
  }
}

extension ReceiptThemeColor {
  func accentColor(for colorScheme: ColorScheme) -> Color {
    let isDark = colorScheme == .dark
    return switch self {
    case .blue:
      isDark ? Color(red: 0.22, green: 0.72, blue: 1) : Color(red: 0.05, green: 0.42, blue: 0.82)
    case .mint:
      isDark ? Color(red: 0.24, green: 0.86, blue: 0.68) : Color(red: 0, green: 0.48, blue: 0.36)
    case .peach:
      isDark ? Color(red: 1, green: 0.56, blue: 0.36) : Color(red: 0.82, green: 0.30, blue: 0.22)
    case .violet:
      isDark ? Color(red: 0.68, green: 0.56, blue: 1) : Color(red: 0.48, green: 0.30, blue: 0.78)
    case .amber:
      isDark ? Color(red: 1, green: 0.72, blue: 0.2) : Color(red: 0.72, green: 0.43, blue: 0.02)
    case .rose:
      isDark ? Color(red: 1, green: 0.4, blue: 0.62) : Color(red: 0.76, green: 0.18, blue: 0.38)
    case .forest:
      isDark ? Color(red: 0.4, green: 0.82, blue: 0.42) : Color(red: 0.12, green: 0.43, blue: 0.18)
    case .indigo:
      isDark ? Color(red: 0.48, green: 0.58, blue: 1) : Color(red: 0.25, green: 0.28, blue: 0.74)
    }
  }

  fileprivate func backgroundColor(for colorScheme: ColorScheme) -> Color {
    let isDark = colorScheme == .dark
    return switch self {
    case .blue:
      isDark ? Color(red: 0.05, green: 0.13, blue: 0.28) : Color(red: 0.78, green: 0.9, blue: 1)
    case .mint:
      isDark ? Color(red: 0.03, green: 0.22, blue: 0.16) : Color(red: 0.76, green: 0.96, blue: 0.87)
    case .peach:
      isDark ? Color(red: 0.32, green: 0.12, blue: 0.06) : Color(red: 1, green: 0.82, blue: 0.7)
    case .violet:
      isDark ? Color(red: 0.18, green: 0.08, blue: 0.32) : Color(red: 0.85, green: 0.79, blue: 1)
    case .amber:
      isDark ? Color(red: 0.3, green: 0.2, blue: 0.03) : Color(red: 1, green: 0.9, blue: 0.58)
    case .rose:
      isDark ? Color(red: 0.3, green: 0.07, blue: 0.14) : Color(red: 1, green: 0.76, blue: 0.84)
    case .forest:
      isDark ? Color(red: 0.04, green: 0.18, blue: 0.08) : Color(red: 0.74, green: 0.91, blue: 0.72)
    case .indigo:
      isDark ? Color(red: 0.08, green: 0.09, blue: 0.3) : Color(red: 0.78, green: 0.82, blue: 1)
    }
  }

  fileprivate var paletteIndex: Int {
    ReceiptThemeColor.allCases.firstIndex(of: self) ?? 0
  }
}
