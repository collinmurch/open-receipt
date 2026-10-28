import SwiftUI

/// Lifts a receipt out of the library or Recently Deleted with its actions: an optional primary
/// action, and one that deletes it. A tap on the lifted receipt runs `onTap`, if any.
struct ReceiptRowFocusView: View {
  /// An action offered under the lifted receipt.
  struct Action {
    let title: String
    let systemImage: String
    let perform: () -> Void
  }

  /// The receipt as its row draws it.
  let row: ReceiptLibraryRow
  /// The list row being copied, in global coordinates.
  let rowFrame: CGRect
  /// Whether the row was long-pressed into focus, so the card starts at the row's pressed size.
  let startsPressed: Bool
  var primaryAction: Action? = nil
  let deleteAction: Action
  var onTap: (() -> Void)? = nil
  let onDismiss: () -> Void

  /// The space between the lifted receipt and its actions.
  private static let actionSpacing: CGFloat = 28

  var body: some View {
    LiftedFocus(onDismiss: onDismiss) { state, proxy in
      let source = proxy.localFrame(of: rowFrame)
      // The receipt settles just above the middle of the screen, with its actions below it.
      let center = CGPoint(
        x: proxy.size.width / 2,
        y: proxy.size.height / 2 - source.height / 2 - LiftedCard.padding.height)
      let actionsTop = CGPoint(
        x: center.x,
        y: center.y + source.height / 2 + LiftedCard.padding.height + Self.actionSpacing)

      row
        .liftedCard(width: source.width, startsPressed: startsPressed, state: state, onTap: onTap)
        .position(state.isInPlace ? center : CGPoint(x: source.midX, y: source.midY))

      actions(state)
        .liftedActions(in: proxy.size, top: actionsTop, state: state)
    }
  }

  private func actions(_ state: LiftedFocusState) -> some View {
    VStack(spacing: 12) {
      if let primaryAction {
        ReceiptActionButton(
          title: primaryAction.title, systemImage: primaryAction.systemImage, tint: .blue
        ) {
          state.dismiss(then: primaryAction.perform)
        }
      }

      Button {
        state.dismiss(then: deleteAction.perform)
      } label: {
        GlassActionLabel(title: deleteAction.title, systemImage: deleteAction.systemImage)
          .foregroundStyle(.red)
      }
      .glassCapsule()
    }
  }
}
