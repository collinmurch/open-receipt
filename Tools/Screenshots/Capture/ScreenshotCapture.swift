import XCTest

/// Captures App Store screens from scripted app states. Run through `make screenshots`, which
/// passes `SCREENSHOTS_OUTPUT` and `SCREENSHOTS_RECEIPT`. Each shot is written in light and dark
/// appearance as a PNG beside JSON manifests that `ScreenshotComposer` reads.
final class ScreenshotCapture: XCTestCase {
  /// Where the running app records highlighted frames.
  private var highlights: URL?

  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testReading() throws {
    let rows = 8
    try capture(
      name: "02-reading",
      scenario: "reading",
      highlight: "receipt-reading-status",
      arguments: ["-ScreenshotReadingRows", "\(rows)"]
    ) { app in
      let label = app.descendants(matching: .any)
        .matching(NSPredicate(format: "label CONTAINS %@", "\(rows) items")).firstMatch
      XCTAssertTrue(label.waitForExistence(timeout: 10), "\(rows) items never appeared")
    }
  }

  @MainActor
  func testSplit() throws {
    try capture(name: "03-split", scenario: "split", highlight: "receipt-participants")
  }

  @MainActor
  func testRequests() throws {
    try capture(name: "05-requests", scenario: "requests", highlight: "request-Jillian")
  }

  @MainActor
  func testBreakdown() throws {
    try capture(name: "04-breakdown", scenario: "requests", highlight: "request-button") { app in
      try self.waitForHighlight("request-Jillian")
      app.staticTexts["Jillian"].firstMatch.tap()
    }
  }

  @MainActor
  func testLibrary() throws {
    try capture(
      name: "01-library", scenario: "library", highlight: "library-row-Cru Food and Wine Bar")
  }

  /// Launches `scenario`, runs `prepare`, waits for the app to draw `highlight`, and writes the
  /// screen with its manifests.
  @MainActor
  private func capture(
    name: String,
    scenario: String,
    highlight: String,
    arguments: [String] = [],
    prepare: (XCUIApplication) throws -> Void = { _ in }
  ) throws {
    let environment = ProcessInfo.processInfo.environment
    guard let output = environment["SCREENSHOTS_OUTPUT"],
      let receipt = environment["SCREENSHOTS_RECEIPT"]
    else { throw XCTSkip("Run through make screenshots.") }

    for appearance in ["light", "dark"] {
      let directory = URL(filePath: output, directoryHint: .isDirectory)
        .appending(path: appearance, directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let highlights = directory.appending(path: "\(name).highlights.json")
      try? FileManager.default.removeItem(at: highlights)
      self.highlights = highlights

      let app = XCUIApplication()
      app.launchArguments =
        [
          "-ScreenshotScenario", scenario,
          "-ScreenshotReceipt", receipt,
          "-ScreenshotAppearance", appearance,
          "-ScreenshotHighlights", highlights.path,
        ] + arguments
      app.launch()

      do {
        try prepare(app)
        try waitForHighlight(highlight)
      } catch {
        try XCUIScreen.main.screenshot().pngRepresentation.write(
          to: directory.appending(path: "\(name)-failure.png"))
        try Data(app.debugDescription.utf8).write(
          to: directory.appending(path: "\(name)-failure.txt"))
        throw error
      }
      settle(for: 2)

      let screenshot = XCUIScreen.main.screenshot()
      let navigationBar = app.navigationBars.firstMatch
      let manifest = CaptureManifest(
        scale: screenshot.image.scale,
        contentTop: navigationBar.exists ? navigationBar.frame.minY : 0)
      try screenshot.pngRepresentation.write(to: directory.appending(path: "\(name).png"))
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(manifest).write(to: directory.appending(path: "\(name).json"))

      app.terminate()
    }
  }

  /// Waits until the running app has recorded where `name` is drawn.
  private func waitForHighlight(_ name: String) throws {
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

  private func settle(for seconds: TimeInterval) {
    let settled = XCTestExpectation(description: "Animations settle")
    _ = XCTWaiter.wait(for: [settled], timeout: seconds)
  }
}

private enum CaptureError: Error, CustomStringConvertible {
  case highlightNeverDrawn(String)

  var description: String {
    switch self {
    case .highlightNeverDrawn(let name): "The app never drew \(name)."
    }
  }
}

/// The captured screen's pixel scale and where its content starts below the status bar, in
/// points. The app writes highlighted frames beside it.
private struct CaptureManifest: Encodable {
  let scale: CGFloat
  let contentTop: CGFloat
}
