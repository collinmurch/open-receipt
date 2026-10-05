import SwiftUI

extension View {
  /// Names Debug and TestFlight builds in the navigation bar, except in App Store screenshots.
  func buildChannelSubtitle() -> some View {
    modifier(BuildChannelSubtitleModifier())
  }

  /// Marks a view that App Store screenshots lift above the screen. Debug builds launched by
  /// `make previews` record where it is drawn; otherwise this does nothing.
  func screenshotHighlight(_ name: String) -> some View {
    modifier(ScreenshotHighlightModifier(name: name))
  }
}

private struct BuildChannelSubtitleModifier: ViewModifier {
  @Environment(ReadingAccess.self) private var access

  @ViewBuilder
  func body(content: Content) -> some View {
    if access.channel.isTesting, !isCapturing {
      content.navigationSubtitle(access.channel.title)
    } else {
      content
    }
  }

  private var isCapturing: Bool {
    #if DEBUG
      return ScreenshotHighlights.isCapturing
    #else
      return false
    #endif
  }
}

private struct ScreenshotHighlightModifier: ViewModifier {
  let name: String

  @ViewBuilder
  func body(content: Content) -> some View {
    #if DEBUG
      if ScreenshotHighlights.isCapturing {
        content.onGeometryChange(for: CGRect.self) { proxy in
          proxy.frame(in: .global)
        } action: { frame in
          ScreenshotHighlights.record(name, frame: frame)
        }
      } else {
        content
      }
    #else
      content
    #endif
  }
}

#if DEBUG
  /// Writes highlighted frames, in points, to the path passed as `-ScreenshotHighlights`.
  @MainActor
  private enum ScreenshotHighlights {
    static let isCapturing = UserDefaults.standard.string(forKey: "ScreenshotScenario") != nil

    private static let url = UserDefaults.standard.string(forKey: "ScreenshotHighlights")
      .map { URL(filePath: $0) }
    private static var frames: [String: CGRect] = [:]

    static func record(_ name: String, frame: CGRect) {
      guard let url else { return }
      frames[name] = frame
      try? JSONEncoder().encode(frames).write(to: url, options: .atomic)
    }
  }
#endif
