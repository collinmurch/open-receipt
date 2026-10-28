import SwiftUI
import UIKit.UIGestureRecognizerSubclass

extension CGFloat {
  /// How much a row grows while pressed, and stays grown while lifted into focus.
  static let pressedRowScale: CGFloat = 1.03
}

extension View {
  /// Makes a list row liftable into focus. Taps and long presses are one gesture rather than a
  /// `Button` or a context menu: a list row's button takes its taps from the row's selection, which
  /// cancels any long press attached to it.
  ///
  /// While `isFocused`, the row reports its global frame so a focused copy can start over it, and
  /// once `isLiftedOut` the row hides beneath that copy. The row is one accessibility element, a
  /// button that taps when it has `onTap` and is enabled.
  func liftableRow(
    isFocused: Bool,
    isLiftedOut: Bool,
    isEnabled: Bool = true,
    onTap: (() -> Void)?,
    onLongPress: @escaping () -> Void,
    onFocusedFrameChange: @escaping (CGRect) -> Void
  ) -> some View {
    modifier(
      LiftableRowModifier(
        isFocused: isFocused,
        isLiftedOut: isLiftedOut,
        isEnabled: isEnabled,
        onTap: onTap,
        onLongPress: onLongPress,
        onFocusedFrameChange: onFocusedFrameChange
      )
    )
  }
}

private struct LiftableRowModifier: ViewModifier {
  let isFocused: Bool
  let isLiftedOut: Bool
  let isEnabled: Bool
  let onTap: (() -> Void)?
  let onLongPress: () -> Void
  let onFocusedFrameChange: (CGRect) -> Void

  @State private var isPressed = false

  private var tapAction: (() -> Void)? {
    isEnabled ? onTap : nil
  }

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect?.self) { proxy in
        isFocused ? proxy.frame(in: .global) : nil
      } action: { frame in
        if let frame { onFocusedFrameChange(frame) }
      }
      // Grows across a long press, then springs back if the finger lifts early.
      .scaleEffect(isPressed ? .pressedRowScale : 1)
      .animation(isPressed ? .pressGrowth : .pressRelease, value: isPressed)
      // The focused copy stands in for the row, so the row hides and returns in one frame.
      .opacity(isLiftedOut ? 0 : 1)
      .transaction(value: isLiftedOut) { $0.animation = nil }
      .contentShape(.rect)
      .gesture(
        RowPressGesture(
          onPressingChanged: { isPressed = $0 },
          onTap: { onTap?() },
          onLongPress: onLongPress,
          isEnabled: isEnabled
        )
      )
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(tapAction == nil ? [] : .isButton)
      .modifier(DefaultAccessibilityAction(action: tapAction))
  }
}

/// Activates the row with VoiceOver, which the press gesture doesn't see as a tap. A row without
/// an action leaves activation to the list, which selects it while editing.
private struct DefaultAccessibilityAction: ViewModifier {
  let action: (() -> Void)?

  func body(content: Content) -> some View {
    if let action {
      content.accessibilityAction(.default, action)
    } else {
      content
    }
  }
}

extension Animation {
  /// A pressed row growing until the press becomes a long press.
  fileprivate static let pressGrowth = Animation.easeOut(
    duration: RowPressRecognizer.pressGrowth)

  /// A pressed row springing back after the finger lifts early.
  fileprivate static let pressRelease = Animation.spring(duration: 0.3, bounce: 0.3)
}

/// Taps and long presses on a row that yield to the list's scrolling. The press only
/// shows once the finger has rested on the row, and any movement before then gives the touch to
/// the list.
private struct RowPressGesture: UIGestureRecognizerRepresentable {
  let onPressingChanged: (Bool) -> Void
  let onTap: () -> Void
  let onLongPress: () -> Void
  var isEnabled = true

  func makeUIGestureRecognizer(context: Context) -> RowPressRecognizer {
    RowPressRecognizer()
  }

  func updateUIGestureRecognizer(_ recognizer: RowPressRecognizer, context: Context) {
    recognizer.isEnabled = isEnabled
  }

  func handleUIGestureRecognizerAction(_ recognizer: RowPressRecognizer, context: Context) {
    switch recognizer.state {
    case .began:
      onPressingChanged(true)
    case .ended:
      onPressingChanged(false)
      switch recognizer.outcome {
      case .tap: onTap()
      case .longPress: onLongPress()
      case nil: break
      }
    case .cancelled, .failed:
      onPressingChanged(false)
    default:
      break
    }
  }
}

/// Stays possible while the finger rests, so a scroll that starts on the row wins. It begins after
/// `pressDelay` and ends as a long press at `longPressDuration`; lifting before then is a tap.
private final class RowPressRecognizer: UIGestureRecognizer {
  enum Outcome {
    case tap
    case longPress
  }

  nonisolated static let pressDelay: Duration = .milliseconds(100)
  nonisolated static let longPressDuration: Duration = .milliseconds(250)
  /// How long a row grows under the finger before the press becomes a long press.
  nonisolated static let pressGrowth = TimeInterval((longPressDuration - pressDelay) / .seconds(1))
  private static let allowableMovement: CGFloat = 10

  private(set) var outcome: Outcome?
  private var startLocation: CGPoint?
  private var timer: Task<Void, Never>?

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    guard startLocation == nil, touches.count == 1, let touch = touches.first else {
      stop()
      return
    }
    startLocation = touch.location(in: view)
    timer = Task { [weak self] in
      try? await Task.sleep(for: Self.pressDelay)
      guard let self, !Task.isCancelled, state == .possible else { return }
      state = .began
      try? await Task.sleep(for: Self.longPressDuration - Self.pressDelay)
      guard !Task.isCancelled, state == .began || state == .changed else { return }
      outcome = .longPress
      state = .ended
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    guard let startLocation, let location = touches.first?.location(in: view) else { return }
    let distance = hypot(location.x - startLocation.x, location.y - startLocation.y)
    if distance > Self.allowableMovement {
      stop()
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    guard state == .possible || state == .began || state == .changed else { return }
    outcome = .tap
    state = .ended
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    stop()
  }

  override func reset() {
    super.reset()
    timer?.cancel()
    timer = nil
    outcome = nil
    startLocation = nil
  }

  private func stop() {
    switch state {
    case .possible: state = .failed
    case .began, .changed: state = .cancelled
    default: break
    }
  }
}
