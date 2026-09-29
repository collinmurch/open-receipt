import SwiftUI

/// A stack of breakdown cards handled like a real deck. Fanned out, dragging either way carries
/// the top card off while the next one rises, and letting go tucks it under the stack. Otherwise
/// only the first card shows, with the rest gathered out of sight behind it.
struct ReceiptBreakdownDeck: View {
  /// Settles quickly and keeps its velocity when a new drag or swipe interrupts it.
  private static let settle = Animation.spring(duration: 0.3, bounce: 0.15)

  /// Each card's image, or nil while it is still being drawn.
  let pages: [UIImage?]
  let pageNames: [String]
  let isFanned: Bool
  @Binding var currentIndex: Int

  @State private var dragOffset: CGFloat = 0

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
      .gesture(swipe(width: width), isEnabled: canSwipe)
    }
    .sensoryFeedback(.selection, trigger: currentIndex)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(pageNames.indices.contains(currentIndex) ? pageNames[currentIndex] : "")
    .accessibilityValue(canSwipe ? "Page \(currentIndex + 1) of \(pages.count)" : "")
    .accessibilityAdjustableAction { direction in
      guard canSwipe else { return }
      switch direction {
      case .increment: withAnimation(Self.settle) { step(by: 1) }
      case .decrement: withAnimation(Self.settle) { step(by: -1) }
      @unknown default: break
      }
    }
  }

  @ViewBuilder
  private func card(at index: Int, width: CGFloat) -> some View {
    let placement = placement(of: index, width: width)
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    Group {
      if let image = pages[index] {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .clipShape(shape)
          // A shape's shadow is drawn from its outline, which stays cheap while the card moves.
          .background {
            shape
              .fill(.black)
              .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
          }
      }
    }
    .scaleEffect(placement.scale)
    .rotationEffect(.degrees(placement.rotation), anchor: .bottom)
    .offset(placement.offset)
    // A card arriving on top fades in faster than the one leaving fades out, so the stack never
    // shows through while they trade places.
    .animation(placement.zIndex == 0 ? .easeOut(duration: 0.16) : .easeIn(duration: 0.32)) {
      $0.opacity(placement.opacity)
    }
    .zIndex(placement.zIndex)
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
      .onChanged { value in
        dragOffset = value.translation.width
      }
      .onEnded { value in
        let isThrown = abs(value.predictedEndTranslation.width) > width * 0.3
        withAnimation(Self.settle) {
          if isThrown { step(by: 1) }
          dragOffset = 0
        }
      }
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
