import SwiftUI

/// Where floating controls along the bottom of the screen sit.
enum ReceiptBottomBar {
  /// The distance from the screen's bottom edge to a control's bottom, matching the capsule of a
  /// system tab bar, so every floating control lines up with the page switcher.
  static let screenEdgeInset: CGFloat = 21
}

extension View {
  /// Floats `bar` over the bottom of the view with its bottom `ReceiptBottomBar.screenEdgeInset`
  /// from the screen's edge, whatever the device's bottom safe area.
  func receiptBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
    modifier(ReceiptBottomBarModifier(bar: bar()))
  }
}

private struct ReceiptBottomBarModifier<Bar: View>: ViewModifier {
  let bar: Bar
  @State private var bottomSafeArea: CGFloat = 0

  func body(content: Content) -> some View {
    content
      .safeAreaBar(edge: .bottom) {
        bar.padding(.bottom, ReceiptBottomBar.screenEdgeInset - bottomSafeArea)
      }
      .background {
        // Measured outside the bar and without the keyboard, so this is the screen's own inset.
        Color.clear
          .ignoresSafeArea(.keyboard)
          .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) { bottomSafeArea = $0 }
      }
  }
}
