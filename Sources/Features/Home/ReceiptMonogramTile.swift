import SwiftUI

/// A small rounded tile carrying a receipt's theme, the only place its color appears in the library.
struct ReceiptMonogramTile: View {
  let style: ReceiptBackgroundStyle
  let initials: String?
  let systemImage: String
  @ScaledMetric(relativeTo: .subheadline) private var side = 42
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: side * 11 / 42, style: .continuous)
    shape
      .fill(
        LinearGradient(
          colors: style.colors(for: colorScheme),
          startPoint: .topLeading,
          endPoint: .bottomTrailing)
      )
      .overlay {
        shape
          .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.5)
      }
      .overlay {
        Group {
          if let initials {
            Text(initials)
              .font(.system(.subheadline, design: .rounded).weight(.bold))
              .transition(.opacity.combined(with: .scale(scale: 0.8)))
          } else {
            Image(systemName: systemImage)
              .font(.subheadline.weight(.semibold))
              .contentTransition(.symbolEffect(.replace))
              .transition(.opacity.combined(with: .scale(scale: 0.8)))
          }
        }
        .foregroundStyle(style.accentColor(for: colorScheme))
      }
      .frame(width: side, height: side)
      .accessibilityHidden(true)
  }
}

enum ReceiptMonogram {
  /// Up to two initials from the first words of a merchant name that start with a letter or digit.
  static func initials(for name: String) -> String? {
    let letters =
      name
      .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "/" })
      .compactMap { $0.first(where: { $0.isLetter || $0.isNumber }) }
      .prefix(2)
    guard !letters.isEmpty else { return nil }
    return String(letters).uppercased()
  }
}
