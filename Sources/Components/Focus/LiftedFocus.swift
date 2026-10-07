import SwiftUI

/// A stage for copies of views lifted out of a list into focus, over a material backdrop that
/// dismisses on tap. The copies start exactly over the views they copy, which stay hidden
/// underneath until the copies settle back over them and `onDismiss` runs.
struct LiftedFocus<Content: View>: View {
  let onDismiss: () -> Void
  /// Runs once the lift settles.
  var onLifted: () -> Void = {}
  @ViewBuilder let content: (LiftedFocusState, GeometryProxy) -> Content

  @State private var isLifted = false
  @State private var isDismissing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let state = LiftedFocusState(
      isLifted: isLifted,
      isDismissing: isDismissing,
      reduceMotion: reduceMotion,
      settle: dismiss(then:)
    )

    GeometryReader { proxy in
      ZStack {
        Rectangle()
          .fill(.regularMaterial)
          .ignoresSafeArea()
          .opacity(isLifted ? 1 : 0)
          .onTapGesture { dismiss(then: nil) }
          .accessibilityHidden(true)

        content(state, proxy)
      }
      .opacity(reduceMotion && !isLifted ? 0 : 1)
    }
    // A bottom bar hiding for focus would otherwise resize the stage mid-lift, jumping the copies.
    .ignoresSafeArea(.container, edges: .bottom)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape) { dismiss(then: nil) }
    .onAppear {
      withAnimation(.lift) {
        isLifted = true
      } completion: {
        onLifted()
      }
    }
  }

  /// Settles the copies back over the views they copy, then runs `action`, so whatever it acts on
  /// is back in place before it moves.
  private func dismiss(then action: (() -> Void)?) {
    guard !isDismissing else { return }
    isDismissing = true
    withAnimation(.settle) {
      isLifted = false
    } completion: {
      onDismiss()
      action?()
    }
  }
}

/// Where a `LiftedFocus` stands in its lift, and how to set it back down.
struct LiftedFocusState {
  /// Whether the copies have risen into focus, rather than resting over the views they copy.
  let isLifted: Bool
  let isDismissing: Bool
  let reduceMotion: Bool
  fileprivate let settle: (_ then: (() -> Void)?) -> Void

  /// Whether the copies stand at their focused positions. Without motion they never travel.
  var isInPlace: Bool { isLifted || reduceMotion }

  /// Settles the copies back, then runs `action`.
  func dismiss(then action: (() -> Void)? = nil) {
    settle(action)
  }
}

enum LiftedCard {
  /// How far a lifted card's background reaches past its content, matching a list row's margins.
  static let padding = CGSize(width: 20, height: 12)
}

extension View {
  /// Draws the view as a card lifted out of a list: a row-wide copy whose background fades in as
  /// it lifts, which a tap sets back down. A row long-pressed into focus starts at its pressed size.
  func liftedCard(width: CGFloat, startsPressed: Bool, state: LiftedFocusState) -> some View {
    frame(width: width)
      .background {
        // The list row's own background stays behind the copy, so the card's fades in as it lifts.
        RoundedRectangle(cornerRadius: 26, style: .continuous)
          .fill(Color(uiColor: .secondarySystemGroupedBackground))
          .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
          .padding(.horizontal, -LiftedCard.padding.width)
          .padding(.vertical, -LiftedCard.padding.height)
          .opacity(state.isLifted ? 1 : 0)
      }
      .scaleEffect(state.isLifted || (startsPressed && !state.isDismissing) ? .pressedRowScale : 1)
      .contentShape(.rect)
      .onTapGesture { state.dismiss() }
  }

  /// Hangs the view's top from `top`, inset like the lifted card, dropping in once the card lifts.
  func liftedActions(in size: CGSize, top: CGPoint, state: LiftedFocusState) -> some View {
    frame(width: size.width - LiftedCard.padding.width * 2)
      .fixedSize(horizontal: false, vertical: true)
      .frame(width: size.width, height: 0, alignment: .top)
      .position(top)
      .opacity(state.isLifted ? 1 : 0)
      .offset(y: state.isInPlace ? 0 : -12)
  }
}

extension GeometryProxy {
  /// `globalFrame` in this proxy's own coordinates.
  func localFrame(of globalFrame: CGRect) -> CGRect {
    let origin = frame(in: .global).origin
    return globalFrame.offsetBy(dx: -origin.x, dy: -origin.y)
  }
}
