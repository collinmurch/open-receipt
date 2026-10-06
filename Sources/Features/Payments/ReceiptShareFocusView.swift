import SwiftUI

/// Lifts one person's share out of the list with its two actions: requesting the share, and
/// sending its breakdown.
struct ReceiptShareFocusView: View {
  let content: ReceiptShareRowContent
  /// The list row being copied, in global coordinates.
  let rowFrame: CGRect
  /// Whether the row was long-pressed into focus, so the card starts at the row's pressed size.
  let startsPressed: Bool
  let request: PreparedPaymentRequest?
  /// Why the share can't be requested, shown in place of the request.
  let unavailableRequestReason: String?
  let breakdown: ReceiptBreakdown?
  /// Where the person's contact card says to message them, which offers messaging the breakdown
  /// alongside sharing it.
  let messageRecipient: Person.IMessage.Recipient?
  let onRequest: (PreparedPaymentRequest) -> Void
  let onMessageBreakdown: (Person.IMessage.Recipient) -> Void
  let onDismiss: () -> Void

  @State private var isChoosingBreakdownDestination = false
  @Namespace private var breakdownGlass

  var body: some View {
    LiftedRowFocus(
      rowFrame: rowFrame,
      startsPressed: startsPressed,
      onDismiss: onDismiss,
      onLifted: prepareBreakdown
    ) {
      content
    } actions: { state in
      actions(state)
    }
  }

  /// Draws the breakdown once the lift settles, so sharing or messaging finds it ready without a
  /// hitch.
  private func prepareBreakdown() {
    if let breakdown { ReceiptBreakdownRenderer.preparePNG(for: breakdown) }
  }

  private func actions(_ state: LiftedFocusState) -> some View {
    VStack(spacing: 12) {
      if let request {
        ReceiptActionButton(
          title: request.title,
          systemImage: request.systemImage,
          tint: request.method.prominentColor
        ) {
          onRequest(request)
          state.dismiss()
        }
      }

      sendBreakdownButton(state)

      if let caption = unavailableRequestReason ?? unavailableBreakdownReason {
        Text(caption)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.top, 4)
      }
    }
  }

  /// Sends the breakdown through the share sheet, or, for a person with a contact card, opens
  /// into a choice between messaging them and the share sheet.
  @ViewBuilder
  private func sendBreakdownButton(_ state: LiftedFocusState) -> some View {
    if let breakdown {
      GlassEffectContainer(spacing: 12) {
        if let messageRecipient, isChoosingBreakdownDestination {
          HStack(spacing: 12) {
            shareLink(breakdown, title: "Share")

            Button {
              onMessageBreakdown(messageRecipient)
              state.dismiss()
            } label: {
              GlassActionLabel(title: "Message \(firstName)", systemImage: "message.fill")
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .glassEffect(
              .regular.tint(PaymentMethod.iMessage.prominentColor).interactive(), in: .capsule
            )
            .glassEffectID(BreakdownGlass.message, in: breakdownGlass)
            .accessibilityHint("Send the breakdown to \(messageRecipient.displayValue)")
          }
        } else if messageRecipient != nil {
          Button {
            withAnimation(.bouncy(duration: 0.4, extraBounce: 0.1)) {
              isChoosingBreakdownDestination = true
            }
          } label: {
            GlassActionLabel(
              title: "Share Individual Breakdown", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(.plain)
          .glassEffect(.regular.interactive(), in: .capsule)
          .glassEffectID(BreakdownGlass.share, in: breakdownGlass)
        } else {
          shareLink(breakdown, title: "Share Individual Breakdown")
        }
      }
      .sensoryFeedback(.selection, trigger: isChoosingBreakdownDestination)
    }
  }

  private func shareLink(_ breakdown: ReceiptBreakdown, title: String) -> some View {
    ShareLink(item: breakdown, preview: SharePreview(breakdown.title, image: breakdown)) {
      GlassActionLabel(title: title, systemImage: "square.and.arrow.up")
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.interactive(), in: .capsule)
    .glassEffectID(BreakdownGlass.share, in: breakdownGlass)
  }

  private var firstName: String {
    ParticipantShortNames.firstName(of: content.share.participant.displayName)
  }

  private var unavailableBreakdownReason: String? {
    breakdown == nil ? "Assign every item before you share the breakdown." : nil
  }
}

private enum BreakdownGlass: Hashable {
  case share
  case message
}
