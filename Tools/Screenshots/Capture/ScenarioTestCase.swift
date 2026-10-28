import XCTest

/// Launches the app into a screenshot scenario and waits on what it draws. `StoreScreenshots`
/// and `DevScreenshot` build on it.
class ScenarioTestCase: XCTestCase {
  /// The highlight the app records once a scenario's screen is in place. It matches
  /// `ScreenshotHighlights.readyName` in the app.
  static let readyHighlight = "scenario-ready"

  /// Where the running app records highlighted frames.
  private var highlights: URL?

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  override func tearDown() async throws {
    await MainActor.run { XCUIDevice.shared.appearance = .light }
  }

  /// Where captures go and the scene the app stages, which `make target` passes. A test run any
  /// other way skips.
  func makeEnvironment(_ target: String) throws -> (output: URL, receipt: String) {
    let environment = ProcessInfo.processInfo.environment
    guard let output = environment["SCREENSHOTS_OUTPUT"],
      let receipt = environment["SCREENSHOTS_RECEIPT"]
    else { throw XCTSkip("Run through make \(target).") }
    return (URL(filePath: output, directoryHint: .isDirectory), receipt)
  }

  /// Launches the app into `scenario` in `appearance`, recording highlighted frames to
  /// `highlights`.
  @MainActor
  func launch(
    scenario: String,
    receipt: String,
    highlights: URL,
    appearance: Appearance = .light,
    arguments: [String] = []
  ) -> XCUIApplication {
    try? FileManager.default.removeItem(at: highlights)
    self.highlights = highlights
    XCUIDevice.shared.appearance = appearance.deviceAppearance
    let app = XCUIApplication()
    app.launchArguments =
      [
        "-ScreenshotScenario", scenario,
        "-ScreenshotReceipt", receipt,
        "-ScreenshotHighlights", highlights.path,
      ] + arguments
    app.launch()
    return app
  }

  /// Waits until the running app has recorded where `name` is drawn.
  func waitForHighlight(_ name: String) throws {
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
      if let highlights,
        let data = try? Data(contentsOf: highlights),
        let frames = try? JSONDecoder().decode([String: CGRect].self, from: data),
        frames[name] != nil
      {
        return
      }
      settle(for: 0.25)
    }
    throw CaptureError.highlightNeverDrawn(name)
  }

  /// Writes the screen as `<name>-failure.png` and the app's accessibility tree as
  /// `<name>-failure.txt`, for working out why a capture failed.
  @MainActor
  func writeFailure(of app: XCUIApplication, named name: String, to directory: URL) throws {
    try XCUIScreen.main.screenshot().pngRepresentation.write(
      to: directory.appending(path: "\(name)-failure.png"))
    try Data(app.debugDescription.utf8).write(
      to: directory.appending(path: "\(name)-failure.txt"))
  }

  func settle(for seconds: TimeInterval) {
    let settled = XCTestExpectation(description: "Animations settle")
    _ = XCTWaiter.wait(for: [settled], timeout: seconds)
  }
}

enum Appearance: String, CaseIterable {
  case light
  case dark

  var deviceAppearance: XCUIDevice.Appearance {
    switch self {
    case .light: .light
    case .dark: .dark
    }
  }
}

enum CaptureError: Error, CustomStringConvertible {
  case highlightNeverDrawn(String)
  case breakdownsNeverWritten
  case unknownAppearance(String)

  var description: String {
    switch self {
    case .highlightNeverDrawn(let name): "The app never drew \(name)."
    case .breakdownsNeverWritten: "The app never wrote the breakdown slips."
    case .unknownAppearance(let name): "Unknown appearance \(name). Use light, dark, or both."
    }
  }
}
