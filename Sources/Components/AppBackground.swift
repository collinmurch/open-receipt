import SwiftUI

/// The still backdrop behind screens outside a receipt, such as the library and Settings. It does
/// not animate, so an idle screen does no drawing.
struct AppBackground: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    MeshGradient(
      width: 3,
      height: 3,
      points: [
        SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
        SIMD2<Float>(0, 0.5), SIMD2<Float>(0.53, 0.47), SIMD2<Float>(1, 0.5),
        SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1),
      ],
      colors: colors,
      background: Color(.systemBackground),
      smoothsColors: true
    )
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }

  private var colors: [Color] {
    colorScheme == .dark ? Self.darkColors : Self.lightColors
  }

  private static let darkColors = [
    Color(red: 0.018, green: 0.02, blue: 0.022),
    Color(red: 0.095, green: 0.07, blue: 0.05),
    Color(red: 0.05, green: 0.075, blue: 0.08),
    Color(red: 0.065, green: 0.06, blue: 0.055),
    Color(red: 0.025, green: 0.03, blue: 0.032),
    Color(red: 0.045, green: 0.07, blue: 0.075),
    Color(red: 0.015, green: 0.018, blue: 0.02),
    Color(red: 0.045, green: 0.05, blue: 0.052),
    Color(red: 0.075, green: 0.06, blue: 0.045),
  ]

  private static let lightColors = [
    Color(red: 0.97, green: 0.955, blue: 0.925),
    Color(red: 0.94, green: 0.9, blue: 0.84),
    Color(red: 0.86, green: 0.89, blue: 0.89),
    Color(red: 0.9, green: 0.9, blue: 0.87),
    Color(red: 0.965, green: 0.955, blue: 0.93),
    Color(red: 0.84, green: 0.875, blue: 0.88),
    Color(red: 0.95, green: 0.925, blue: 0.875),
    Color(red: 0.89, green: 0.9, blue: 0.89),
    Color(red: 0.93, green: 0.9, blue: 0.85),
  ]
}
