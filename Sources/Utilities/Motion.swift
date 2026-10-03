import SwiftUI

extension Animation {
  /// A row lifting out of its list into focus.
  static let lift = Animation.spring(duration: 0.35, bounce: 0.2)

  /// A focused row returning to its list, and other changes of focus or editing.
  static let settle = Animation.smooth(duration: 0.35)

  /// A quick change of selection, such as choosing people or items.
  static let selectionChange = Animation.smooth(duration: 0.25)

  /// Glass controls morphing into one another.
  static let glassMorph = Animation.bouncy(duration: 0.5, extraBounce: 0.1)

  /// A pressed row growing until the press becomes a long press.
  static let pressGrowth = Animation.easeOut(duration: ReceiptRowPressRecognizer.pressGrowth)

  /// A pressed row springing back after the finger lifts early.
  static let pressRelease = Animation.spring(duration: 0.3, bounce: 0.3)
}

extension View {
  /// Grows a row across a long press, then springs it back if the finger lifts early.
  func pressScale(_ isPressed: Bool) -> some View {
    scaleEffect(isPressed ? ReceiptItemRowContent.pressedScale : 1)
      .animation(isPressed ? .pressGrowth : .pressRelease, value: isPressed)
  }
}
