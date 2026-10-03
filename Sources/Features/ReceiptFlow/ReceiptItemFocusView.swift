import SwiftUI

/// Lifts one item and the people strip out of the receipt so people can be assigned to that item
/// directly. Both start exactly over the views they copy, which stay hidden underneath until the
/// copies settle back over them.
struct ReceiptItemFocusView: View {
  /// How far the card's background reaches past the item, matching a list row's margins.
  private static let cardPadding = CGSize(width: 20, height: 12)

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
  var addTransition: (id: AnyHashable, namespace: Namespace.ID)?
  let onDismiss: () -> Void

  @State private var isLifted = false
  @State private var isDismissing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let origin = proxy.frame(in: .global).origin
      let row = rowFrame.offsetBy(dx: -origin.x, dy: -origin.y)
      let strip = stripFrame.offsetBy(dx: -origin.x, dy: -origin.y)
      let layout = LiftedLayout(
        size: proxy.size, stripHeight: strip.height, cardPadding: Self.cardPadding.height)
      let isInPlace = isLifted || reduceMotion

      ZStack {
        Rectangle()
          .fill(.regularMaterial)
          .ignoresSafeArea()
          .opacity(isLifted ? 1 : 0)
          .onTapGesture(perform: dismiss)
          .accessibilityHidden(true)

        if let item = draft.items.first(where: { $0.id == itemID }) {
          card(item, width: row.width)
            .position(isInPlace ? layout.cardTop : CGPoint(x: row.midX, y: row.minY))

          ParticipantStrip(
            participants: draft.participants,
            amountsOwed: amountsOwed,
            currency: draft.displayCurrency,
            selectedParticipantIDs: isLifted ? item.participantIDs : stripSelection,
            onSelect: toggleAssignment,
            onManagePeople: onManagePeople,
            addTransition: addTransition
          )
          .frame(width: strip.width)
          .position(isInPlace ? layout.stripCenter : CGPoint(x: strip.midX, y: strip.midY))

          Text("Tap the people who shared this item")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .frame(width: proxy.size.width)
            .position(layout.captionCenter)
            .opacity(isLifted ? 1 : 0)
        }
      }
      .opacity(reduceMotion && !isLifted ? 0 : 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape, dismiss)
    .onAppear {
      withAnimation(.lift) { isLifted = true }
    }
  }

  /// The item, pinned by its top edge so it grows downward, away from the people, as they're
  /// assigned.
  private func card(_ item: ReceiptDraftItem, width: CGFloat) -> some View {
    ReceiptItemRowContent(
      item: item,
      assignedParticipants: draft.participants(assignedTo: item),
      isAssignedToSelection: false,
      isEditing: false,
      displayCurrency: draft.displayCurrency
    )
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
    .fixedSize(horizontal: false, vertical: true)
    .frame(width: width, height: 0, alignment: .top)
  }

  private var cardScale: CGFloat {
    isLifted || (startsPressed && !isDismissing) ? ReceiptItemRowContent.pressedScale : 1
  }

  private func toggleAssignment(_ participantID: ReceiptParticipant.ID) {
    haptic.play(.selection)
    withAnimation(.selectionChange) {
      draft.toggleAssignment(of: [participantID], to: itemID)
    }
  }

  private func dismiss() {
    guard !isDismissing else { return }
    isDismissing = true
    withAnimation(.settle) {
      isLifted = false
    } completion: {
      onDismiss()
    }
  }
}

/// Where the lifted views settle: the people strip just above the middle of the screen, the
/// instructions above it, and the item below it.
private struct LiftedLayout {
  private static let spacing: CGFloat = 16

  let size: CGSize
  let stripHeight: CGFloat
  let cardPadding: CGFloat

  private var stripBottom: CGFloat { size.height / 2 - Self.spacing }

  var stripCenter: CGPoint {
    CGPoint(x: size.width / 2, y: stripBottom - stripHeight / 2)
  }

  var cardTop: CGPoint {
    CGPoint(x: size.width / 2, y: stripBottom + Self.spacing + cardPadding)
  }

  var captionCenter: CGPoint {
    CGPoint(x: size.width / 2, y: stripBottom - stripHeight - Self.spacing - 8)
  }
}
