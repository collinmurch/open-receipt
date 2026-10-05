import SwiftUI

extension View {
  /// Slides the view up from below the screen as `isPresented` turns on, a beat behind the views
  /// before it in `order`, and back down with the rest when it turns off. With Reduce Motion the
  /// view fades in place instead.
  func rising(
    _ isPresented: Bool, from distance: CGFloat, order: Int, reduceMotion: Bool
  ) -> some View {
    offset(y: isPresented || reduceMotion ? 0 : distance)
      .opacity(isPresented || !reduceMotion ? 1 : 0)
      .transaction(value: isPresented) { transaction in
        guard isPresented else { return }
        transaction.animation = transaction.animation?.delay(Double(order) * 0.045)
      }
  }
}
