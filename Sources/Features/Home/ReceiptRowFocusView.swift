import SwiftUI

/// Lifts a receipt out of the library or Recently Deleted with its actions: an optional primary
/// action, and one that deletes it.
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
  let primaryAction: Action?
  /// A color dark enough to stay legible under the primary action's white label.
  let primaryTint: Color
  let deleteAction: Action
  let onDismiss: () -> Void

  var body: some View {
    LiftedFocus(onDismiss: onDismiss) { state, proxy in
      let source = proxy.localFrame(of: rowFrame)
      let layout = LiftedRowLayout(size: proxy.size, rowHeight: source.height)

      row
        .liftedCard(width: source.width, startsPressed: startsPressed, state: state)
        .position(state.isInPlace ? layout.cardCenter : CGPoint(x: source.midX, y: source.midY))

      actions(state)
        .liftedActions(in: proxy.size, top: layout.actionsTop, state: state)
    }
  }

  private func actions(_ state: LiftedFocusState) -> some View {
    VStack(spacing: 12) {
      if let primaryAction {
        ReceiptActionButton(
          title: primaryAction.title, systemImage: primaryAction.systemImage, tint: primaryTint
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
      .buttonStyle(.plain)
      .glassEffect(.regular.interactive(), in: .capsule)
    }
  }
}
