import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// A two-finger drag across a scrolling list, like the list's own two-finger selection. The
/// list's scrolling waits on it, so one finger still scrolls and two fingers sweep, and holding
/// the fingers near the list's top or bottom edge scrolls it.
struct TwoFingerSweepGesture: UIGestureRecognizerRepresentable {
  var isEnabled = true
  /// The fingers' location in global coordinates, each time they move or the list scrolls under
  /// them.
  let onChanged: (CGPoint) -> Void
  let onEnded: () -> Void

  func makeUIGestureRecognizer(context: Context) -> TwoFingerSweepRecognizer {
    let recognizer = TwoFingerSweepRecognizer()
    recognizer.minimumNumberOfTouches = 2
    recognizer.maximumNumberOfTouches = 2
    return recognizer
  }

  func updateUIGestureRecognizer(_ recognizer: TwoFingerSweepRecognizer, context: Context) {
    recognizer.isEnabled = isEnabled
  }

  func handleUIGestureRecognizerAction(_ recognizer: TwoFingerSweepRecognizer, context: Context) {
    switch recognizer.state {
    case .began, .changed:
      onChanged(context.converter.location(in: .global))
    case .ended, .cancelled, .failed:
      onEnded()
    default:
      break
    }
  }
}

/// A two-finger pan that the enclosing scroll view's pan waits on. It fails as soon as a lone
/// finger moves, so single-finger scrolling starts without delay, and while it runs it scrolls the
/// scroll view when the fingers rest near an edge.
final class TwoFingerSweepRecognizer: UIPanGestureRecognizer {
  /// How far a lone finger can drift while a second one lands.
  private static let singleTouchAllowance: CGFloat = 10
  /// How close to the visible edge the fingers start scrolling, and the speed at the edge itself.
  private static let autoscrollZone: CGFloat = 64
  private static let maxAutoscrollSpeed: CGFloat = 900

  private var firstTouchStart: CGPoint?
  private weak var scrollView: UIScrollView?
  private var displayLink: CADisplayLink?

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    if firstTouchStart == nil {
      firstTouchStart = touches.first?.location(in: nil)
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    if state == .possible, (event.touches(for: self)?.count ?? 0) < 2,
      let firstTouchStart, let location = touches.first?.location(in: nil),
      hypot(location.x - firstTouchStart.x, location.y - firstTouchStart.y)
        > Self.singleTouchAllowance
    {
      state = .failed
      return
    }
    super.touchesMoved(touches, with: event)
    if state == .began, displayLink == nil {
      let displayLink = CADisplayLink(target: self, selector: #selector(autoscroll(_:)))
      displayLink.add(to: .main, forMode: .common)
      self.displayLink = displayLink
    }
  }

  override func reset() {
    super.reset()
    displayLink?.invalidate()
    displayLink = nil
    firstTouchStart = nil
  }

  override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    guard isEnabled, let view,
      let scrollView = otherGestureRecognizer.view as? UIScrollView,
      otherGestureRecognizer === scrollView.panGestureRecognizer,
      view.isDescendant(of: scrollView) || scrollView.isDescendant(of: view)
    else { return false }
    self.scrollView = scrollView
    return true
  }

  /// Scrolls toward the edge the fingers rest near, faster the closer they are, and reports the
  /// sweep as changed so the rows under the fingers are read again.
  @objc private func autoscroll(_ displayLink: CADisplayLink) {
    guard let scrollView, state == .began || state == .changed else { return }
    let visible = scrollView.bounds.inset(by: scrollView.adjustedContentInset)
    let y = location(in: scrollView).y
    let zone = Self.autoscrollZone
    let depth: CGFloat =
      if y < visible.minY + zone {
        -min(1, (visible.minY + zone - y) / zone)
      } else if y > visible.maxY - zone {
        min(1, (y - (visible.maxY - zone)) / zone)
      } else {
        0
      }
    guard depth != 0 else { return }

    let insets = scrollView.adjustedContentInset
    let minOffset = -insets.top
    let maxOffset = max(
      minOffset, scrollView.contentSize.height + insets.bottom - scrollView.bounds.height)
    let step =
      depth * Self.maxAutoscrollSpeed * (displayLink.targetTimestamp - displayLink.timestamp)
    let offset = min(max(scrollView.contentOffset.y + step, minOffset), maxOffset)
    guard offset != scrollView.contentOffset.y else { return }
    scrollView.contentOffset.y = offset
    state = .changed
  }
}
