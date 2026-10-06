import SwiftUI

/// A stack of breakdown cards handled like a real deck. Fanned out, dragging either way carries
/// the top card off while the next one rises, and letting go tucks it under the stack. Otherwise
/// only the first card shows, with the rest gathered out of sight behind it. Tapping the top card
/// opens it, zooming out of the card registered under its index in `transition`.
struct ReceiptBreakdownDeck: View {
  /// Settles quickly and keeps its velocity when a new drag or swipe interrupts it.
  private static let settle = Spring(duration: 0.19, bounce: 0.15)
  /// Carries a thrown card on from the finger's speed until it is clear of the stack.
  private static let carry = Spring(duration: 0.09, bounce: 0)
  /// How far, as a share of the deck's width, the top card travels before it can go under.
  private static let clearance: CGFloat = 0.55
  /// How long, in seconds, a card thrown from already clear of the stack coasts at the finger's
  /// speed before turning back under it.
  private static let coast: CGFloat = 0.025

  /// Each card's image, or nil while it is still being drawn.
  let pages: [UIImage?]
  let pageNames: [String]
  let isFanned: Bool
  @Binding var currentIndex: Int
  let transition: Namespace.ID
  let onOpen: () -> Void

  @State private var dragOffset: CGFloat = 0
  @State private var isTossing = false
  /// How far the finger had already moved when the current drag took hold of the top card, or
  /// nil while no drag has. A drag that starts mid-toss takes hold once the toss ends.
  @State private var dragOrigin: CGFloat?
  @GestureState private var isDragging = false

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      ZStack {
        ForEach(pages.indices, id: \.self) { index in
          card(at: index, width: width)
        }
      }
      .frame(width: width, height: proxy.size.height)
      .contentShape(.rect)
      // The swipe stays enabled through a toss and ignores it instead, since a gesture enabled
      // partway through a touch can be cancelled without ever ending.
      .gesture(swipe(width: width), isEnabled: canSwipe)
    }
    // A drag the system cancels never ends, which would leave the top card wherever the finger
    // last had it.
    .onChange(of: isDragging) { _, isDragging in
      guard !isDragging, dragOrigin != nil else { return }
      dragOrigin = nil
      withAnimation(.spring(Self.settle)) { dragOffset = 0 }
    }
    // Gathering the deck resets it to the first card, which the page picker already plays for.
    .sensoryFeedback(.selection, trigger: currentIndex) { _, _ in isFanned }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(pageNames.indices.contains(currentIndex) ? pageNames[currentIndex] : "")
    .accessibilityValue(canSwipe ? "Page \(currentIndex + 1) of \(pages.count)" : "")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { onOpen() }
    .accessibilityAdjustableAction { direction in
      guard canSwipe else { return }
      switch direction {
      case .increment: withAnimation(.spring(Self.settle)) { step(by: 1) }
      case .decrement: withAnimation(.spring(Self.settle)) { step(by: -1) }
      @unknown default: break
      }
    }
  }

  @ViewBuilder
  private func card(at index: Int, width: CGFloat) -> some View {
    let placement = placement(of: index, width: width)
    Group {
      if let image = pages[index] {
        ReceiptBreakdownCardImage(
          image: image, cornerRadius: 18, sourceID: index, transition: transition)
      }
    }
    .scaleEffect(placement.scale)
    .rotationEffect(.degrees(placement.rotation), anchor: .bottom)
    .offset(placement.offset)
    // A card arriving on top fades in faster than the one leaving fades out, so the stack never
    // shows through while they trade places.
    .animation(placement.zIndex == 0 ? .easeOut(duration: 0.09) : .easeIn(duration: 0.2)) {
      $0.opacity(placement.opacity)
    }
    .zIndex(placement.zIndex)
    .onTapGesture {
      if !isTossing { onOpen() }
    }
    .allowsHitTesting(placement.zIndex == 0)
  }

  private var canSwipe: Bool {
    isFanned && pages.count > 1
  }

  /// How far below the top card `index` sits, counting around the deck from the current card.
  /// Unfanned, everything but the first card sits out of sight.
  private func depth(of index: Int) -> Int {
    guard isFanned else { return index == 0 ? 0 : pages.count }
    return (index - currentIndex + pages.count) % pages.count
  }

  private func placement(of index: Int, width: CGFloat) -> Placement {
    let depth = depth(of: index)
    guard isFanned else { return depth == 0 ? .top : .gathered(depth: depth) }

    if depth == 0 {
      return Placement(
        scale: 1,
        rotation: dragOffset / 16,
        offset: CGSize(width: dragOffset, height: abs(dragOffset) / 12),
        opacity: 1,
        zIndex: 0)
    }
    let rest = Placement.resting(depth: depth)
    guard depth == 1, dragOffset != 0 else { return rest }
    let progress = min(abs(dragOffset) / (width * 0.5), 1)
    return rest.interpolated(to: .top, by: progress * 0.7)
  }

  private func swipe(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 2)
      .updating($isDragging) { _, isDragging, _ in isDragging = true }
      .onChanged { value in
        guard !isTossing else { return }
        let origin = dragOrigin ?? value.translation.width
        dragOrigin = origin
        dragOffset = value.translation.width - origin
      }
      .onEnded { value in
        guard let origin = dragOrigin else { return }
        dragOrigin = nil
        let predicted = value.predictedEndTranslation.width - origin
        let velocity = value.velocity.width
        if abs(predicted) > width * 0.3 {
          toss(toward: predicted < 0 ? -1 : 1, velocity: velocity, width: width)
        } else {
          let initialVelocity = relativeVelocity(velocity, toward: 0)
          withAnimation(.interpolatingSpring(Self.settle, initialVelocity: initialVelocity)) {
            dragOffset = 0
          }
        }
      }
  }

  /// Sends the top card to the back of the deck. It carries on from the finger's speed until it
  /// is clear of the stack, so it never appears to pass through the cards it tucks under, and
  /// turns back under them before it stops, so it never pauses at the edge.
  private func toss(toward direction: CGFloat, velocity: CGFloat, width: CGFloat) {
    let distance = max(width * Self.clearance, abs(dragOffset) + abs(velocity) * Self.coast)
    let target = direction * distance
    // With nowhere left to carry it, no animation would run to call the completion.
    guard abs(target - dragOffset) > 1 else {
      tuck()
      return
    }
    let initialVelocity = relativeVelocity(velocity, toward: target)
    isTossing = true
    withAnimation(
      .interpolatingSpring(Self.carry, initialVelocity: initialVelocity),
      completionCriteria: .logicallyComplete
    ) {
      dragOffset = target
    } completion: {
      tuck()
    }
  }

  /// Interpolating springs add to one still running, so the card turns back from wherever its
  /// carry has it, at the speed it has there.
  private func tuck() {
    withAnimation(.interpolatingSpring(Self.settle)) {
      step(by: 1)
      dragOffset = 0
    }
    isTossing = false
  }

  /// The finger's `velocity` as a share of the distance left to `target` each second, which is
  /// how springs take their initial velocity.
  private func relativeVelocity(_ velocity: CGFloat, toward target: CGFloat) -> Double {
    let distance = target - dragOffset
    guard abs(distance) > 1 else { return 0 }
    return velocity / distance
  }

  private func step(by offset: Int) {
    currentIndex = (currentIndex + offset + pages.count) % pages.count
  }
}

/// Where a card sits: its size, tilt about its bottom edge, position, and stacking.
private struct Placement {
  static let top = Placement(scale: 1, rotation: 0, offset: .zero, opacity: 1, zIndex: 0)

  let scale: CGFloat
  let rotation: Double
  let offset: CGSize
  let opacity: Double
  let zIndex: Double

  /// The top card centered, the next two fanned out to either side, and the rest waiting out of
  /// sight behind them.
  static func resting(depth: Int) -> Placement {
    switch depth {
    case 0:
      top
    case 1:
      Placement(
        scale: 0.94, rotation: -4, offset: CGSize(width: -22, height: 10), opacity: 1,
        zIndex: -1)
    case 2:
      Placement(
        scale: 0.94, rotation: 4, offset: CGSize(width: 22, height: 10), opacity: 1,
        zIndex: -2)
    default:
      Placement(
        scale: 0.9, rotation: 0, offset: CGSize(width: 0, height: 14), opacity: 0,
        zIndex: -Double(depth))
    }
  }

  /// A card waiting out of sight directly behind a lone top card.
  static func gathered(depth: Int) -> Placement {
    Placement(scale: 0.96, rotation: 0, offset: .zero, opacity: 0, zIndex: -Double(depth))
  }

  /// This placement moved `fraction` of the way to `target`, keeping this one's stacking.
  func interpolated(to target: Placement, by fraction: CGFloat) -> Placement {
    Placement(
      scale: scale + (target.scale - scale) * fraction,
      rotation: rotation + (target.rotation - rotation) * fraction,
      offset: CGSize(
        width: offset.width + (target.offset.width - offset.width) * fraction,
        height: offset.height + (target.offset.height - offset.height) * fraction),
      opacity: opacity + (target.opacity - opacity) * fraction,
      zIndex: zIndex)
  }
}
