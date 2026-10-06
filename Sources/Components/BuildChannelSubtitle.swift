import SwiftUI

extension View {
  /// Names Debug and TestFlight builds in the navigation bar, except in App Store screenshots.
  func buildChannelSubtitle() -> some View {
    modifier(BuildChannelSubtitleModifier())
  }
}

private struct BuildChannelSubtitleModifier: ViewModifier {
  @Environment(ReadingAccess.self) private var access

  @ViewBuilder
  func body(content: Content) -> some View {
    if access.channel.isTesting, !ScreenshotHighlights.isCapturing {
      content.navigationSubtitle(access.channel.title)
    } else {
      content
    }
  }
}
