import SwiftUI
import UIKit.UIGestureRecognizerSubclass

extension View {
  /// Closes the keyboard when a tap lands anywhere outside a row with a text field, like on a
  /// button, another row, a header, or the empty space below the list. The tap still reaches
  /// whatever was under it.
  func dismissesKeyboardOnTap() -> some View {
    gesture(KeyboardDismissTapGesture())
  }
}

private struct KeyboardDismissTapGesture: UIGestureRecognizerRepresentable {
  func makeUIGestureRecognizer(context: Context) -> KeyboardDismissTapRecognizer {
    let recognizer = KeyboardDismissTapRecognizer()
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesEnded = false
    return recognizer
  }
}

/// Ends editing when a lone touch lifts without moving, then fails, so it never wins a touch
/// from the list or the controls under it. A touch that starts in a row holding a text field is
/// left alone, since tapping anywhere in those rows focuses their field.
private final class KeyboardDismissTapRecognizer: UIGestureRecognizer {
  private static let slop: CGFloat = 10
  private var start: CGPoint?

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    guard touches.count == 1, let touch = touches.first, start == nil,
      touch.view?.isInTextFieldRow != true
    else {
      state = .failed
      return
    }
    start = touch.location(in: view)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    guard let start, let touch = touches.first else { return }
    let location = touch.location(in: view)
    if hypot(location.x - start.x, location.y - start.y) > Self.slop {
      state = .failed
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    if start != nil { view?.window?.endEditing(true) }
    state = .failed
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    state = .failed
  }

  override func reset() {
    super.reset()
    start = nil
  }
}

extension UIView {
  fileprivate var isInTextFieldRow: Bool {
    let ancestors = sequence(first: self, next: \.superview)
    if let row = ancestors.first(where: { $0 is UICollectionViewCell }) {
      return row.containsTextInput
    }
    return ancestors.contains { $0 is UITextField || $0 is UITextView }
  }

  private var containsTextInput: Bool {
    self is UITextField || self is UITextView || subviews.contains { $0.containsTextInput }
  }
}
