import SwiftUI

/// Someone a group message reaches, with the address from their contact card.
struct GroupMessageRecipient: Equatable {
  let name: String
  let recipient: Person.IMessage.Recipient
}

/// Lifts the receipt's breakdown over the payments page to message it to everyone or share it
/// anywhere, as the overview alone or followed by each person's breakdown.
struct ReceiptGroupShareView: View {
  private static let presentAnimation = Animation.spring(duration: 0.5, bounce: 0.18)
  private static let dismissAnimation = Animation.smooth(duration: 0.32)
  private static let fanAnimation = Animation.spring(duration: 0.4, bounce: 0.15)

  /// The overview, then each person's breakdown.
  let breakdowns: [ReceiptBreakdown]
  let messageRecipients: [GroupMessageRecipient]
  /// People the message leaves out for having no phone number or email on a contact card.
  let unreachableNames: [String]
  @Binding var includesEveryBreakdown: Bool
  let onMessage: ([ReceiptBreakdown]) -> Void
  let onDismiss: () -> Void

  @State private var isPresented = false
  @State private var isDismissing = false
  @State private var pageImages: [UIImage?]
  @State private var currentPage = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    breakdowns: [ReceiptBreakdown],
    messageRecipients: [GroupMessageRecipient],
    unreachableNames: [String],
    includesEveryBreakdown: Binding<Bool>,
    onMessage: @escaping ([ReceiptBreakdown]) -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.breakdowns = breakdowns
    self.messageRecipients = messageRecipients
    self.unreachableNames = unreachableNames
    _includesEveryBreakdown = includesEveryBreakdown
    self.onMessage = onMessage
    self.onDismiss = onDismiss
    _pageImages = State(initialValue: Array(repeating: nil, count: breakdowns.count))
  }

  var body: some View {
    GeometryReader { proxy in
      let riseDistance = proxy.size.height + proxy.safeAreaInsets.bottom

      ZStack {
        Rectangle()
          .fill(.regularMaterial)
          .ignoresSafeArea()
          .opacity(isPresented ? 1 : 0)
          .onTapGesture(perform: dismiss)
          .accessibilityHidden(true)

        VStack(spacing: 22) {
          VStack(spacing: 12) {
            ReceiptBreakdownDeck(
              pages: pageImages,
              pageNames: pageNames,
              isFanned: includesEveryBreakdown,
              currentIndex: $currentPage
            )
            .frame(maxHeight: proxy.size.height * 0.48)
            .rising(isPresented, from: riseDistance, order: 0, reduceMotion: reduceMotion)

            HStack(spacing: 0) {
              Text(currentPageName)
                .contentTransition(.opacity)
              Text(" · \(currentPage + 1) of \(breakdowns.count)")
                .contentTransition(.numericText(value: Double(currentPage)))
            }
            .font(.footnote.weight(.medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .animation(.smooth(duration: 0.25), value: currentPage)
            .opacity(includesEveryBreakdown ? 1 : 0)
            .accessibilityHidden(true)
            .rising(isPresented, from: riseDistance, order: 1, reduceMotion: reduceMotion)
          }

          Picker("Pages", selection: pagesSelection) {
            Text("Overview").tag(false)
            Text("All Pages").tag(true)
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 280)
          .rising(isPresented, from: riseDistance, order: 1, reduceMotion: reduceMotion)

          actions
            .rising(isPresented, from: riseDistance, order: 2, reduceMotion: reduceMotion)

          if !unreachableNames.isEmpty {
            Text("Missing iMessage contact for \(unreachableNames.joined(separator: ", "))")
              .font(.footnote)
              .foregroundStyle(.orange)
              .multilineTextAlignment(.center)
              .rising(isPresented, from: riseDistance, order: 3, reduceMotion: reduceMotion)
          }
        }
        .padding(.horizontal, 20)
        .frame(width: proxy.size.width, height: proxy.size.height)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape, dismiss)
    .sensoryFeedback(.selection, trigger: includesEveryBreakdown)
    .task {
      // The cards on screen are drawn before the deck rises so they travel up with it. The rest
      // are drawn once it settles, each after the previous one has faded in, so drawing never
      // lands in the middle of a rise or a swipe.
      let visibleCount = includesEveryBreakdown ? min(3, breakdowns.count) : 1
      for index in 0..<visibleCount {
        pageImages[index] = renderPage(index)
      }
      await animate(Self.presentAnimation) { isPresented = true }
      for index in breakdowns.indices where pageImages[index] == nil {
        guard !Task.isCancelled else { return }
        let image = renderPage(index)
        await animate(.smooth(duration: 0.25)) { pageImages[index] = image }
      }
    }
    // Cards take their accent from the appearance, so a change while open redraws them.
    .onChange(of: breakdowns) {
      pageImages = breakdowns.indices.map(renderPage)
    }
  }

  private func animate(_ animation: Animation, _ body: () -> Void) async {
    await withCheckedContinuation { continuation in
      withAnimation(animation, body, completion: { continuation.resume() })
    }
  }

  /// Draws the page at full scale so the same drawing is encoded for sharing and messaging.
  private func renderPage(_ index: Int) -> UIImage? {
    let image = ReceiptBreakdownRenderer.image(for: breakdowns[index])
    ReceiptBreakdownRenderer.preparePNG(for: breakdowns[index], from: image)
    return image
  }

  /// Fans the deck out or gathers it back onto the overview in one animation, so the overview
  /// returns to the top as the other cards collapse behind it.
  private var pagesSelection: Binding<Bool> {
    Binding {
      includesEveryBreakdown
    } set: { includesEvery in
      withAnimation(Self.fanAnimation) {
        includesEveryBreakdown = includesEvery
        if !includesEvery { currentPage = 0 }
      }
    }
  }

  private var pageNames: [String] {
    breakdowns.map { breakdown in
      switch breakdown.content {
      case .group: "Overview"
      case .person(let share): share.participant.displayName
      }
    }
  }

  private var currentPageName: String {
    pageNames.indices.contains(currentPage) ? pageNames[currentPage] : ""
  }

  private var actions: some View {
    GlassEffectContainer(spacing: 12) {
      HStack(spacing: 12) {
        ShareLink(
          items: selectedBreakdowns,
          preview: { SharePreview($0.title, image: $0) }
        ) {
          GlassActionLabel(title: "Share", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)

        if !messageRecipients.isEmpty {
          Button {
            onMessage(selectedBreakdowns)
            dismiss()
          } label: {
            GlassActionLabel(title: messageTitle, systemImage: "message.fill")
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
          .glassEffect(
            .regular.tint(PaymentMethod.iMessage.prominentColor).interactive(), in: .capsule
          )
          .screenshotHighlight("group-message-button")
          .accessibilityHint(
            "Message \(messageRecipients.map(\.name).formatted()) with the breakdown")
        }
      }
    }
  }

  private var selectedBreakdowns: [ReceiptBreakdown] {
    includesEveryBreakdown ? breakdowns : Array(breakdowns.prefix(1))
  }

  private var messageTitle: String {
    guard messageRecipients.count == 1, let only = messageRecipients.first else {
      return "Message Group"
    }
    return "Message \(ParticipantShortNames.firstName(of: only.name))"
  }

  private func dismiss() {
    guard !isDismissing else { return }
    isDismissing = true
    withAnimation(Self.dismissAnimation) {
      isPresented = false
    } completion: {
      onDismiss()
    }
  }
}
