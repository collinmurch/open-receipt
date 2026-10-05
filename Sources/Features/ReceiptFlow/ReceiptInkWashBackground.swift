import SwiftUI

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
  @State private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
  /// Resting motion for a background shown outside a receipt, which has no shared motion. It is
  /// static because a `@State` initial value is rebuilt, and discarded, on every parent update.
  private static let restingMotion = ReceiptBackgroundMotion()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.receiptBackgroundMotion) private var sharedMotion
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let motion = sharedMotion ?? Self.restingMotion
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
    .task {
      // Read again on appearing, since changes while off screen go unobserved.
      isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
      for await _ in NotificationCenter.default.notifications(
        named: .NSProcessInfoPowerStateDidChange)
      {
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
      }
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

private struct ReceiptInkWashPalette {
  let base: Color
  let primary: Color
  let secondary: Color
  let highlight: Color
  let bloom: Color
  let grainSeed: Float
}

extension ReceiptBackgroundStyle {
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
}
