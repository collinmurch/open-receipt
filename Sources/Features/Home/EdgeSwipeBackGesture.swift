import SwiftUI
import UIKit

struct EdgeSwipeBackGesture: UIGestureRecognizerRepresentable {
  let onChanged: (CGFloat) -> Void
  let onEnded: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

  func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
    let recognizer = UIScreenEdgePanGestureRecognizer()
    recognizer.edges = .left
    return recognizer
  }

  func handleUIGestureRecognizerAction(
    _ recognizer: UIScreenEdgePanGestureRecognizer, context: Context
  ) {
    switch recognizer.state {
    case .began, .changed:
      onChanged(max(0, recognizer.translation(in: recognizer.view).x))
    case .ended:
      onEnded(
        recognizer.translation(in: recognizer.view).x,
        recognizer.velocity(in: recognizer.view).x)
    case .cancelled, .failed:
      onEnded(0, 0)
    default:
      break
    }
  }
}
