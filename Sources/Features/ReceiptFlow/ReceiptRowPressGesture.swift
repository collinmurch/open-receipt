import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// Taps and long presses on a receipt item row that yield to the list's scrolling. The press only
/// shows once the finger has rested on the row, and any movement before then gives the touch to
/// the list.
struct ReceiptRowPressGesture: UIGestureRecognizerRepresentable {
  let onPressingChanged: (Bool) -> Void
  let onTap: () -> Void
  let onLongPress: () -> Void
  var isEnabled = true

  func makeUIGestureRecognizer(context: Context) -> ReceiptRowPressRecognizer {
    ReceiptRowPressRecognizer()
  }

  func updateUIGestureRecognizer(_ recognizer: ReceiptRowPressRecognizer, context: Context) {
    recognizer.isEnabled = isEnabled
  }

  func handleUIGestureRecognizerAction(_ recognizer: ReceiptRowPressRecognizer, context: Context) {
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
final class ReceiptRowPressRecognizer: UIGestureRecognizer {
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
