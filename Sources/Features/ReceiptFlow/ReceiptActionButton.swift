import SwiftUI

/// A screen's primary action: a capsule of tinted glass pinned to the bottom of the screen. The glass
/// is a `glassEffect`, so the button can morph with other glass in a `GlassEffectContainer`.
struct ReceiptActionButton: View {
  let title: String
  let systemImage: String
  /// A color dark enough to stay legible under the button's white label.
  let tint: Color
  let action: () -> Void
  @ScaledMetric(relativeTo: .body) private var height: CGFloat = 50

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Text(title)
        Image(systemName: systemImage)
      }
      .font(.body.weight(.semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 22)
      .frame(minHeight: height)
      .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.tint(tint).interactive(), in: .capsule)
  }
}
