import SwiftUI

/// Lifts a copy of one list row into focus, with `actions` hanging below it. An `accessory` fills
/// the space above the row, which settles lower to make room for it.
struct LiftedRowFocus<Card: View, Accessory: View, Actions: View>: View {
  /// The list row being copied, in global coordinates.
  let rowFrame: CGRect
  /// Whether the row was long-pressed into focus, so the card starts at the row's pressed size.
  let startsPressed: Bool
  let onDismiss: () -> Void
  /// Runs once the lift settles.
  var onLifted: () -> Void = {}
  @ViewBuilder let card: Card
  let accessory: (() -> Accessory)?
  @ViewBuilder let actions: (LiftedFocusState) -> Actions

  var body: some View {
    LiftedFocus(onDismiss: onDismiss, onLifted: onLifted) { state, proxy in
      let source = proxy.localFrame(of: rowFrame)
      let layout = LiftedRowLayout(
        size: proxy.size, rowHeight: source.height, hasAccessory: accessory != nil)

      if let accessory {
        let frame = layout.accessoryFrame
        accessory()
          .frame(width: frame.width, height: frame.height)
          .scaleEffect(state.isInPlace ? 1 : 0.92, anchor: .bottom)
          .opacity(state.isLifted ? 1 : 0)
          .position(x: frame.midX, y: frame.midY)
      }

      card
        .liftedCard(width: source.width, startsPressed: startsPressed, state: state)
        .position(state.isInPlace ? layout.cardCenter : CGPoint(x: source.midX, y: source.midY))

      actions(state)
        .liftedActions(in: proxy.size, top: layout.actionsTop, state: state)
    }
  }
}

extension LiftedRowFocus where Accessory == EmptyView {
  init(
    rowFrame: CGRect,
    startsPressed: Bool,
    onDismiss: @escaping () -> Void,
    onLifted: @escaping () -> Void = {},
    @ViewBuilder card: () -> Card,
    @ViewBuilder actions: @escaping (LiftedFocusState) -> Actions
  ) {
    self.init(
      rowFrame: rowFrame,
      startsPressed: startsPressed,
      onDismiss: onDismiss,
      onLifted: onLifted,
      card: card,
      accessory: nil,
      actions: actions)
  }
}

/// Where a lifted row settles: just above the middle of the screen, with its actions below the
/// middle. With an accessory, the row settles lower and the accessory fills the space above it.
private struct LiftedRowLayout {
  private static let spacing: CGFloat = 28
  private static let accessoryDrop: CGFloat = 0.1

  let size: CGSize
  let rowHeight: CGFloat
  let hasAccessory: Bool

  var cardCenter: CGPoint {
    let drop = hasAccessory ? size.height * Self.accessoryDrop : 0
    return CGPoint(
      x: size.width / 2,
      y: size.height / 2 - rowHeight / 2 - LiftedCard.padding.height + drop)
  }

  var actionsTop: CGPoint {
    CGPoint(
      x: size.width / 2,
      y: cardCenter.y + rowHeight / 2 + LiftedCard.padding.height + Self.spacing)
  }

  var accessoryFrame: CGRect {
    let top = Self.spacing / 2
    let bottom = cardCenter.y - rowHeight / 2 - LiftedCard.padding.height - Self.spacing
    return CGRect(
      x: LiftedCard.padding.width,
      y: top,
      width: size.width - LiftedCard.padding.width * 2,
      height: max(bottom - top, 0))
  }
}
