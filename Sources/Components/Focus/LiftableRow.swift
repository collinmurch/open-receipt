import SwiftUI

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
  /// once `isLiftedOut` the row hides beneath that copy.
  func liftableRow(
    isFocused: Bool,
    isLiftedOut: Bool,
    isEnabled: Bool = true,
    onTap: @escaping () -> Void,
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
  let onTap: () -> Void
  let onLongPress: () -> Void
  let onFocusedFrameChange: (CGRect) -> Void

  @State private var isPressed = false

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
        ReceiptRowPressGesture(
          onPressingChanged: { isPressed = $0 },
          onTap: onTap,
          onLongPress: onLongPress,
          isEnabled: isEnabled
        )
      )
  }
}

extension Animation {
  /// A pressed row growing until the press becomes a long press.
  fileprivate static let pressGrowth = Animation.easeOut(
    duration: ReceiptRowPressRecognizer.pressGrowth)

  /// A pressed row springing back after the finger lifts early.
  fileprivate static let pressRelease = Animation.spring(duration: 0.3, bounce: 0.3)
}
