import SwiftUI

/// Someone a group message reaches, with the address from their contact card.
struct GroupMessageRecipient: Equatable {
  let name: String
  let recipient: Person.IMessage.Recipient
}

/// Lifts the receipt's breakdown over the payments page to message it to everyone or share it
/// anywhere, as the overview alone or followed by each person's breakdown.
struct ReceiptGroupShareView: View {
  private static let presentAnimation = Animation.spring(duration: 0.4, bounce: 0.2)
  private static let dismissAnimation = Animation.smooth(duration: 0.3)
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

            Text(pageCaption)
              .font(.footnote.weight(.medium).monospacedDigit())
              .foregroundStyle(.secondary)
              .contentTransition(.numericText())
              .animation(.smooth(duration: 0.25), value: currentPage)
              .opacity(includesEveryBreakdown ? 1 : 0)
              .accessibilityHidden(true)
          }

          Picker("Pages", selection: pagesSelection) {
            Text("Overview").tag(false)
            Text("All Pages").tag(true)
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 280)

          actions

          if !unreachableNames.isEmpty {
            Text("Missing iMessage for \(unreachableNames.joined(separator: ", "))")
              .font(.footnote)
              .foregroundStyle(.orange)
              .multilineTextAlignment(.center)
          }
        }
        .padding(.horizontal, 20)
        .frame(width: proxy.size.width, height: proxy.size.height)
        .opacity(isPresented ? 1 : 0)
        .offset(y: isPresented || reduceMotion ? 0 : 48)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape, dismiss)
    .sensoryFeedback(.selection, trigger: includesEveryBreakdown)
    .onAppear {
      withAnimation(Self.presentAnimation) { isPresented = true }
    }
    .task {
      // Draws one card per frame, overview first, so the overlay animates in without a stall.
      for index in breakdowns.indices {
        let image = ReceiptBreakdownRenderer.image(for: breakdowns[index], scale: 2)
        withAnimation(.smooth(duration: 0.25)) { pageImages[index] = image }
        await Task.yield()
      }
    }
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

  private var pageCaption: String {
    let name = pageNames.indices.contains(currentPage) ? pageNames[currentPage] : ""
    return "\(name) · \(currentPage + 1) of \(breakdowns.count)"
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
    let firstName = only.name.split(whereSeparator: \.isWhitespace).first.map(String.init)
    return "Message \(firstName ?? only.name)"
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
