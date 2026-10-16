import XCTest

/// Captures App Store screens from scripted app states. Run through `make previews`, which
/// passes `SCREENSHOTS_OUTPUT` and `SCREENSHOTS_RECEIPT`. Each shot is written in light and dark
/// appearance as a PNG beside JSON manifests that `ScreenshotComposer` reads.
final class StoreScreenshots: ScenarioTestCase {
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
    try capture(name: "03-split", scenario: "split", highlight: "receipt-participants") { app in
      try self.waitForHighlight("receipt-participants")
      for name in ["Jillian", "Will"] {
        app.buttons[name].firstMatch.tap()
      }
    }
  }

  @MainActor
  func testRequests() throws {
    try capture(name: "04-requests", scenario: "requests", highlight: "request-Jillian") { app in
      try self.waitForHighlight("request-Jillian")
      self.scrollPaymentsToEnd(app)
    }
  }

  @MainActor
  func testShare() throws {
    try capture(
      name: "05-share",
      scenario: "share",
      highlight: "group-message-button",
      arguments: ["-groupShareIncludesEveryBreakdown", "YES"]
    ) { app in
      try self.waitForHighlight("request-Jillian")
      self.scrollPaymentsToEnd(app)
      app.buttons["Share Group Breakdown"].firstMatch.tap()
    }
  }

  @MainActor
  func testLibrary() throws {
    try capture(
      name: "01-library", scenario: "library", highlight: "library-row-Comedy Cellar")
  }

  /// The receipt being read for the App Store search result, in the header's colors.
  @MainActor
  func testSearch() throws {
    let rows = 8
    try capture(
      name: "search",
      scenario: "reading",
      highlight: "receipt-reading-status",
      arguments: [
        "-ScreenshotReadingRows", "\(rows)",
        "-ScreenshotBackgroundStyle", Self.artworkStyle,
      ]
    ) { app in
      let label = app.descendants(matching: .any)
        .matching(NSPredicate(format: "label CONTAINS %@", "\(rows) items")).firstMatch
      XCTAssertTrue(label.waitForExistence(timeout: 10), "\(rows) items never appeared")
    }
  }

  /// Everyone's breakdown slips for the App Store header, which the app draws itself. They are
  /// written to `breakdowns` beside the appearance directories.
  @MainActor
  func testHeader() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let output = environment["SCREENSHOTS_OUTPUT"],
      let receipt = environment["SCREENSHOTS_RECEIPT"]
    else { throw XCTSkip("Run through make previews.") }

    let directory = URL(filePath: output, directoryHint: .isDirectory)
      .appending(path: "breakdowns", directoryHint: .isDirectory)
    try? FileManager.default.removeItem(at: directory)
    let app = XCUIApplication()
    app.launchArguments = [
      "-ScreenshotScenario", "breakdowns",
      "-ScreenshotReceipt", receipt,
      "-ScreenshotBreakdowns", directory.path,
      "-ScreenshotBackgroundStyle", Self.artworkStyle,
    ]
    app.launch()
    defer { app.terminate() }

    let manifest = directory.appending(path: "breakdowns.json")
    let deadline = Date().addingTimeInterval(20)
    while !FileManager.default.fileExists(atPath: manifest.path) {
      guard Date() < deadline else { throw CaptureError.breakdownsNeverWritten }
      settle(for: 0.25)
    }
  }

  /// The receipt colors of the header and search artwork, which match the app icon.
  private static let artworkStyle = "mint/blue"

  /// The in-app purchase's review screenshot, which App Review sees instead of customers.
  @MainActor
  func testPaywall() throws {
    try capture(
      name: "06-paywall", scenario: "paywall", highlight: "unlimited-reading-purchase")
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
    let app = launch(
      scenario: scenario, receipt: receipt, highlights: highlights, arguments: arguments)
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
        try writeFailure(of: app, named: name, to: directory)
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

  /// Scrolls the payments page down to its group breakdown button, which otherwise rests under
  /// the page switcher.
  @MainActor
  private func scrollPaymentsToEnd(_ app: XCUIApplication) {
    app.swipeUp()
    settle(for: 1)
  }
}

/// The captured screen's pixel scale and where its content starts below the status bar, in
/// points. The app writes highlighted frames beside it.
private struct CaptureManifest: Encodable {
  let scale: CGFloat
  let contentTop: CGFloat
}
