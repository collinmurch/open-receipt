import SwiftUI

/// A screen's primary action: a capsule of tinted glass pinned to the bottom of the screen. The glass
/// is a `glassEffect`, so the button can morph with other glass in a `GlassEffectContainer`.
struct ReceiptActionButton: View {
  let title: String
  let systemImage: String
  /// A color dark enough to stay legible under the button's white label.
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      GlassActionLabel(title: title, systemImage: systemImage)
        .foregroundStyle(.white)
    }
    .glassCapsule(tint: tint)
  }
}

/// A glass capsule button's title and symbol, sized like `ReceiptActionButton`, or smaller to fit
/// a share card when `isCompact`.
struct GlassActionLabel: View {
  let title: String
  let systemImage: String
  var isCompact = false
  @ScaledMetric(relativeTo: .body) private var height: CGFloat = 50
  @ScaledMetric(relativeTo: .body) private var compactHeight: CGFloat = 46

  var body: some View {
    HStack(spacing: isCompact ? 8 : 10) {
      Text(title)
        .buttonTitleLineLimit()
        .minimumScaleFactor(isCompact ? 0.8 : 1)
      Image(systemName: systemImage)
    }
    .font(.body.weight(.semibold))
    .padding(.horizontal, isCompact ? 16 : 22)
    .frame(minHeight: isCompact ? compactHeight : height)
    .contentShape(.capsule)
  }
}

extension View {
  /// Makes a button a capsule of interactive glass, tinted with `tint` when there is one.
  func glassCapsule(tint: Color? = nil) -> some View {
    buttonStyle(.plain)
      .glassEffect(.regular.tint(tint).interactive(), in: .capsule)
  }

  /// Keeps a button's title to one line, letting it wrap, centered, at accessibility sizes where
  /// one line would cut it off.
  func buttonTitleLineLimit() -> some View {
    modifier(ButtonTitleLineLimit())
  }
}

private struct ButtonTitleLineLimit: ViewModifier {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func body(content: Content) -> some View {
    content
      .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
      .multilineTextAlignment(.center)
  }
}
