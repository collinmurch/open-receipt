import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// A tap on a list that lands outside its rows, such as on a section header or the empty space
/// below the last row. Touches that start in a row are left to the row, and the tap never delays
/// or cancels the list's own touches.
struct ListBackgroundTapGesture: UIGestureRecognizerRepresentable {
  var isEnabled = true
  let onTap: () -> Void

  func makeUIGestureRecognizer(context: Context) -> ListBackgroundTapRecognizer {
    let recognizer = ListBackgroundTapRecognizer()
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesEnded = false
    return recognizer
  }

  func updateUIGestureRecognizer(_ recognizer: ListBackgroundTapRecognizer, context: Context) {
    recognizer.isEnabled = isEnabled
  }

  func handleUIGestureRecognizerAction(_ recognizer: ListBackgroundTapRecognizer, context: Context)
  {
    if recognizer.state == .ended { onTap() }
  }
}

/// A tap that fails as soon as a touch starts inside a collection view cell, which is how a list
/// draws its rows.
final class ListBackgroundTapRecognizer: UITapGestureRecognizer {
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    if touches.contains(where: { $0.view?.isInCollectionViewCell == true }) {
      state = .failed
      return
    }
    super.touchesBegan(touches, with: event)
  }
}

extension UIView {
  fileprivate var isInCollectionViewCell: Bool {
    sequence(first: self, next: \.superview).contains { $0 is UICollectionViewCell }
  }
}
