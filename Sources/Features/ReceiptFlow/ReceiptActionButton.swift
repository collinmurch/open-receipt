import SwiftUI

/// The floating glass capsule used for a receipt's primary action, tinted with its theme.
struct ReceiptActionButton: View {
  let title: String
  let systemImage: String
  let style: ReceiptBackgroundStyle
  let action: () -> Void
  @ScaledMetric(relativeTo: .body) private var height: CGFloat = 50
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Text(title)
        Image(systemName: systemImage)
      }
      .font(.body.weight(.semibold))
      .padding(.horizontal, 18)
      .frame(minHeight: height)
      .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .foregroundStyle(style.accentColor(for: colorScheme))
    .glassEffect(.regular.interactive(), in: .capsule)
  }
}
