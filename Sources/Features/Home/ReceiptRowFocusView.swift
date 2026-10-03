import SwiftUI

/// Lifts a receipt out of the library or Recently Deleted with its actions: an optional primary
/// action, and one that deletes it. The receipt starts exactly over the row it copies, which stays
/// hidden underneath until the copy settles back over it.
struct ReceiptRowFocusView: View {
  /// An action offered under the lifted receipt.
  struct Action {
    let title: String
    let systemImage: String
    let perform: () -> Void
  }

  /// How far the card's background reaches past the receipt, matching a list row's margins.
  private static let cardPadding = CGSize(width: 20, height: 12)

  /// The receipt as its row draws it.
  let row: ReceiptLibraryRow
  /// The list row being copied, in global coordinates.
  let rowFrame: CGRect
  /// Whether the row was long-pressed into focus, so the card starts at the row's pressed size.
  let startsPressed: Bool
  let primaryAction: Action?
  /// A color dark enough to stay legible under the primary action's white label.
  let primaryTint: Color
  let deleteAction: Action
  let onDismiss: () -> Void

  @State private var isLifted = false
  @State private var isDismissing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let origin = proxy.frame(in: .global).origin
      let row = rowFrame.offsetBy(dx: -origin.x, dy: -origin.y)
      let layout = LiftedRowLayout(
        size: proxy.size, rowHeight: row.height, cardPadding: Self.cardPadding.height)
      let isInPlace = isLifted || reduceMotion

      ZStack {
        Rectangle()
          .fill(.regularMaterial)
          .ignoresSafeArea()
          .opacity(isLifted ? 1 : 0)
          .onTapGesture(perform: dismiss)
          .accessibilityHidden(true)

        card(width: row.width)
          .position(isInPlace ? layout.cardCenter : CGPoint(x: row.midX, y: row.midY))

        actions
          .frame(width: proxy.size.width - Self.cardPadding.width * 2)
          .fixedSize(horizontal: false, vertical: true)
          .frame(width: proxy.size.width, height: 0, alignment: .top)
          .position(layout.actionsTop)
          .opacity(isLifted ? 1 : 0)
          .offset(y: isLifted || reduceMotion ? 0 : -12)
      }
      .opacity(reduceMotion && !isLifted ? 0 : 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape, dismiss)
    .onAppear {
      withAnimation(.lift) {
        isLifted = true
      }
    }
  }

  private func card(width: CGFloat) -> some View {
    row
      .frame(width: width)
      .background {
        // The list row's own background stays behind the copy, so the card's fades in as it lifts.
        RoundedRectangle(cornerRadius: 26, style: .continuous)
          .fill(Color(uiColor: .secondarySystemGroupedBackground))
          .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
          .padding(.horizontal, -Self.cardPadding.width)
          .padding(.vertical, -Self.cardPadding.height)
          .opacity(isLifted ? 1 : 0)
      }
      .scaleEffect(cardScale)
      .contentShape(.rect)
      .onTapGesture(perform: dismiss)
  }

  private var actions: some View {
    VStack(spacing: 12) {
      if let primaryAction {
        ReceiptActionButton(
          title: primaryAction.title, systemImage: primaryAction.systemImage, tint: primaryTint
        ) {
          dismiss(then: primaryAction.perform)
        }
      }

      Button {
        dismiss(then: deleteAction.perform)
      } label: {
        GlassActionLabel(title: deleteAction.title, systemImage: deleteAction.systemImage)
          .foregroundStyle(.red)
      }
      .buttonStyle(.plain)
      .glassEffect(.regular.interactive(), in: .capsule)
    }
  }

  private var cardScale: CGFloat {
    isLifted || (startsPressed && !isDismissing) ? ReceiptItemRowContent.pressedScale : 1
  }

  private func dismiss() {
    dismiss(then: nil)
  }

  /// Settles the card back over its row, then runs `action`, so the row it acts on is back in
  /// place before it moves.
  private func dismiss(then action: (() -> Void)?) {
    guard !isDismissing else { return }
    isDismissing = true
    withAnimation(.settle) {
      isLifted = false
    } completion: {
      onDismiss()
      action?()
    }
  }
}
