import SwiftUI

extension View {
  /// Marks a view that App Store screenshots lift above the screen. Debug builds launched by
  /// `make previews` record where it is drawn; otherwise this does nothing.
  func screenshotHighlight(_ name: String) -> some View {
    modifier(ScreenshotHighlightModifier(name: name))
  }
}

private struct ScreenshotHighlightModifier: ViewModifier {
  let name: String

  @ViewBuilder
  func body(content: Content) -> some View {
    if ScreenshotHighlights.isCapturing {
      content.onGeometryChange(for: CGRect.self) { proxy in
        proxy.frame(in: .global)
      } action: { frame in
        ScreenshotHighlights.record(name, frame: frame)
      }
    } else {
      content
    }
  }
}

/// Writes highlighted frames, in points, to the path passed as `-ScreenshotHighlights`.
@MainActor
enum ScreenshotHighlights {
  /// Whether `make previews` launched this build to capture screenshots, which only Debug builds
  /// can be.
  static let isCapturing: Bool = {
    #if DEBUG
      UserDefaults.standard.string(forKey: "ScreenshotScenario") != nil
    #else
      false
    #endif
  }()

  private static let url = UserDefaults.standard.string(forKey: "ScreenshotHighlights")
    .map { URL(filePath: $0) }
  private static var frames: [String: CGRect] = [:]

  static func record(_ name: String, frame: CGRect) {
    guard isCapturing, let url else { return }
    frames[name] = frame
    try? JSONEncoder().encode(frames).write(to: url, options: .atomic)
  }
}
