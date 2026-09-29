import SwiftUI

/// Lifts one person's share out of the list with its two actions: requesting the share, and
/// sending its breakdown. The share starts exactly over the row it copies, which stays hidden
/// underneath until the copy settles back over it.
struct ReceiptShareFocusView: View {
  /// How far the card's background reaches past the share, matching a list row's margins.
  private static let cardPadding = CGSize(width: 20, height: 12)
  private static let liftAnimation = Animation.spring(duration: 0.35, bounce: 0.2)
  private static let returnAnimation = Animation.smooth(duration: 0.35)

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

  @State private var isLifted = false
  @State private var isDismissing = false
  @State private var isChoosingBreakdownDestination = false
  @Namespace private var breakdownGlass
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let origin = proxy.frame(in: .global).origin
      let row = rowFrame.offsetBy(dx: -origin.x, dy: -origin.y)
      let layout = LiftedLayout(
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
      withAnimation(Self.liftAnimation) { isLifted = true }
    }
  }

  private func card(width: CGFloat) -> some View {
    content
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
      if let request {
        ReceiptActionButton(
          title: request.title,
          systemImage: request.systemImage,
          tint: request.method.prominentColor
        ) {
          onRequest(request)
          dismiss()
        }
      }

      sendBreakdownButton

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
  private var sendBreakdownButton: some View {
    if let breakdown {
      GlassEffectContainer(spacing: 12) {
        if let messageRecipient, isChoosingBreakdownDestination {
          HStack(spacing: 12) {
            shareLink(breakdown, title: "Share")

            Button {
              onMessageBreakdown(messageRecipient)
              dismiss()
            } label: {
              GlassActionLabel(title: "Message \(firstName)", systemImage: "message.fill")
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
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
    let name = content.share.participant.displayName
    return name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
  }

  private var unavailableBreakdownReason: String? {
    breakdown == nil ? "Assign every item before you share the breakdown." : nil
  }

  private var cardScale: CGFloat {
    isLifted || (startsPressed && !isDismissing) ? ReceiptItemRowContent.pressedScale : 1
  }

  private func dismiss() {
    guard !isDismissing else { return }
    isDismissing = true
    withAnimation(Self.returnAnimation) {
      isLifted = false
    } completion: {
      onDismiss()
    }
  }
}

private enum BreakdownGlass: Hashable {
  case share
  case message
}

/// A glass capsule button's title and symbol, sized like `ReceiptActionButton`.
struct GlassActionLabel: View {
  let title: String
  let systemImage: String
  @ScaledMetric(relativeTo: .body) private var height: CGFloat = 50

  var body: some View {
    HStack(spacing: 10) {
      Text(title)
        .lineLimit(1)
      Image(systemName: systemImage)
    }
    .font(.body.weight(.semibold))
    .padding(.horizontal, 22)
    .frame(minHeight: height)
    .contentShape(.capsule)
  }
}

/// Where the lifted views settle: the share just above the middle of the screen, and its actions
/// below the middle.
private struct LiftedLayout {
  private static let spacing: CGFloat = 28

  let size: CGSize
  let rowHeight: CGFloat
  let cardPadding: CGFloat

  var cardCenter: CGPoint {
    CGPoint(x: size.width / 2, y: size.height / 2 - rowHeight / 2 - cardPadding)
  }

  var actionsTop: CGPoint {
    CGPoint(x: size.width / 2, y: cardCenter.y + rowHeight / 2 + cardPadding + Self.spacing)
  }
}
