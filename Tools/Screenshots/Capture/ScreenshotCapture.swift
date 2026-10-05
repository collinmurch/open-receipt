import XCTest

/// Captures App Store screens from scripted app states. Run through `make previews`, which
/// passes `SCREENSHOTS_OUTPUT` and `SCREENSHOTS_RECEIPT`. Each shot is written in light and dark
/// appearance as a PNG beside JSON manifests that `ScreenshotComposer` reads.
final class ScreenshotCapture: XCTestCase {
  /// Where the running app records highlighted frames.
  private var highlights: URL?

  override func setUp() {
    continueAfterFailure = false
  }

  override func tearDown() async throws {
    await MainActor.run { XCUIDevice.shared.appearance = .light }
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
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Jillian")).firstMatch.tap()
    }
  }

  @MainActor
  func testShare() throws {
    try capture(
      name: "06-share",
      scenario: "share",
      highlight: "group-message-button",
      arguments: ["-groupShareIncludesEveryBreakdown", "YES"]
    ) { app in
      try self.waitForHighlight("request-Jillian")
      app.buttons["Share Breakdown"].firstMatch.tap()
    }
  }

  @MainActor
  func testLibrary() throws {
    try capture(
      name: "01-library", scenario: "library", highlight: "library-row-Cru Food and Wine Bar")
  }

  /// The in-app purchase's review screenshot, which App Review sees instead of customers.
  @MainActor
  func testPaywall() throws {
    try capture(
      name: "07-paywall", scenario: "paywall", highlight: "unlimited-reading-purchase")
  }

  /// Launches `scenario`, runs `prepare`, waits for the app to draw `highlight`, and writes the
  /// screen with its manifests in light appearance, then again in dark from the same launch.
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
    else { throw XCTSkip("Run through make previews.") }

    let root = URL(filePath: output, directoryHint: .isDirectory)
    let directories = try Appearance.allCases.map { appearance in
      let directory = root.appending(path: appearance.rawValue, directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try? FileManager.default.removeItem(at: directory.appending(path: "\(name).highlights.json"))
      return directory
    }
    let highlights = root.appending(path: "\(name).highlights.json")
    try? FileManager.default.removeItem(at: highlights)
    self.highlights = highlights

    XCUIDevice.shared.appearance = .light
    let app = XCUIApplication()
    app.launchArguments =
      [
        "-ScreenshotScenario", scenario,
        "-ScreenshotReceipt", receipt,
        "-ScreenshotHighlights", highlights.path,
      ] + arguments
    app.launch()
    defer { app.terminate() }

    for (appearance, directory) in zip(Appearance.allCases, directories) {
      do {
        if appearance == .light {
          try prepare(app)
        } else {
          XCUIDevice.shared.appearance = .dark
        }
        try waitForHighlight(highlight)
      } catch {
        try XCUIScreen.main.screenshot().pngRepresentation.write(
          to: directory.appending(path: "\(name)-failure.png"))
        try Data(app.debugDescription.utf8).write(
          to: directory.appending(path: "\(name)-failure.txt"))
        throw error
      }
      settle(for: 1)

      let screenshot = XCUIScreen.main.screenshot()
      let navigationBar = app.navigationBars.firstMatch
      let manifest = CaptureManifest(
        scale: screenshot.image.scale,
        contentTop: navigationBar.exists ? navigationBar.frame.minY : 0)
      try screenshot.pngRepresentation.write(to: directory.appending(path: "\(name).png"))
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(manifest).write(to: directory.appending(path: "\(name).json"))
      try FileManager.default.copyItem(
        at: highlights, to: directory.appending(path: "\(name).highlights.json"))
    }
    try FileManager.default.removeItem(at: highlights)
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

private enum Appearance: String, CaseIterable {
  case light
  case dark
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
