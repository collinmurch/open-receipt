import SwiftUI

/// Lifts a copy of one list row into focus, with `actions` hanging below it.
struct LiftedRowFocus<Card: View, Actions: View>: View {
  /// The list row being copied, in global coordinates.
  let rowFrame: CGRect
  /// Whether the row was long-pressed into focus, so the card starts at the row's pressed size.
  let startsPressed: Bool
  let onDismiss: () -> Void
  /// Runs once the lift settles.
  var onLifted: () -> Void = {}
  @ViewBuilder let card: Card
  @ViewBuilder let actions: (LiftedFocusState) -> Actions

  var body: some View {
    LiftedFocus(onDismiss: onDismiss, onLifted: onLifted) { state, proxy in
      let source = proxy.localFrame(of: rowFrame)
      let layout = LiftedRowLayout(size: proxy.size, rowHeight: source.height)

      card
        .liftedCard(width: source.width, startsPressed: startsPressed, state: state)
        .position(state.isInPlace ? layout.cardCenter : CGPoint(x: source.midX, y: source.midY))

      actions(state)
        .liftedActions(in: proxy.size, top: layout.actionsTop, state: state)
    }
  }
}

/// Where a lifted row settles: just above the middle of the screen, with its actions below the
/// middle.
private struct LiftedRowLayout {
  private static let spacing: CGFloat = 28

  let size: CGSize
  let rowHeight: CGFloat

  var cardCenter: CGPoint {
    CGPoint(x: size.width / 2, y: size.height / 2 - rowHeight / 2 - LiftedCard.padding.height)
  }

  var actionsTop: CGPoint {
    CGPoint(
      x: size.width / 2,
      y: cardCenter.y + rowHeight / 2 + LiftedCard.padding.height + Self.spacing)
  }
}
