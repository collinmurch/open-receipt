import SwiftUI

/// Lifts one item and the people strip out of the receipt so people can be assigned to that item
/// directly.
struct ReceiptItemFocusView: View {
  let draft: ReceiptDraft
  let itemID: ReceiptDraftItem.ID
  /// The list row and people strip being copied, in global coordinates.
  let rowFrame: CGRect
  /// Whether the row was long-pressed into focus, so the card starts at the row's pressed size.
  let startsPressed: Bool
  let stripFrame: CGRect
  /// The people selected in the strip being copied, which the copy fades from and back to.
  let stripSelection: Set<ReceiptParticipant.ID>
  let amountsOwed: [ReceiptParticipant.ID: Double]
  @Binding var haptic: HapticEvent
  let onManagePeople: () -> Void
  let addTransition: (id: AnyHashable, namespace: Namespace.ID)
  let onDismiss: () -> Void

  var body: some View {
    LiftedFocus(onDismiss: onDismiss) { state, proxy in
      let row = proxy.localFrame(of: rowFrame)
      let strip = proxy.localFrame(of: stripFrame)
      let layout = LiftedLayout(size: proxy.size, stripHeight: strip.height)

      if let item = draft.items.first(where: { $0.id == itemID }) {
        card(item, width: row.width, state: state)
          .position(state.isInPlace ? layout.cardTop : CGPoint(x: row.midX, y: row.minY))

        ParticipantStrip(
          participants: draft.participants,
          amountsOwed: amountsOwed,
          currency: draft.displayCurrency,
          selectedParticipantIDs: state.isLifted ? item.participantIDs : stripSelection,
          onSelect: toggleAssignment,
          onManagePeople: onManagePeople,
          addTransition: addTransition
        )
        .frame(width: strip.width)
        .position(state.isInPlace ? layout.stripCenter : CGPoint(x: strip.midX, y: strip.midY))

        Text("Tap the people who shared this item")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
          .frame(width: proxy.size.width)
          .position(layout.captionCenter)
          .opacity(state.isLifted ? 1 : 0)
      }
    }
  }

  /// The item, pinned by its top edge so it grows downward, away from the people, as they're
  /// assigned.
  private func card(_ item: ReceiptDraftItem, width: CGFloat, state: LiftedFocusState)
    -> some View
  {
    ReceiptItemRowContent(
      item: item,
      assignedParticipants: draft.participants(assignedTo: item),
      isAssignedToSelection: false,
      isEditing: false,
      displayCurrency: draft.displayCurrency
    )
    .liftedCard(width: width, startsPressed: startsPressed, state: state)
    .fixedSize(horizontal: false, vertical: true)
    .frame(width: width, height: 0, alignment: .top)
  }

  private func toggleAssignment(_ participantID: ReceiptParticipant.ID) {
    haptic.play(.selection)
    withAnimation(.selectionChange) {
      draft.toggleAssignment(of: [participantID], to: itemID)
    }
  }
}

/// Where the lifted views settle: the people strip just above the middle of the screen, the
/// instructions above it, and the item below it.
private struct LiftedLayout {
  private static let spacing: CGFloat = 16

  let size: CGSize
  let stripHeight: CGFloat

  private var stripBottom: CGFloat { size.height / 2 - Self.spacing }

  var stripCenter: CGPoint {
    CGPoint(x: size.width / 2, y: stripBottom - stripHeight / 2)
  }

  var cardTop: CGPoint {
    CGPoint(x: size.width / 2, y: stripBottom + Self.spacing + LiftedCard.padding.height)
  }

  var captionCenter: CGPoint {
    CGPoint(x: size.width / 2, y: stripBottom - stripHeight - Self.spacing - 8)
  }
}
