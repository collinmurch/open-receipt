import XCTest

/// Captures one app screen for checking UI work. Run through `make screenshot`, which passes
/// `SCREENSHOTS_SCENARIO`, `SCREENSHOTS_NAME`, `SCREENSHOTS_APPEARANCE`, `SCREENSHOTS_TEXT_SIZE`,
/// `SCREENSHOTS_OUTPUT`, and `SCREENSHOTS_RECEIPT`. It writes `<name>-<appearance>.png` for each appearance and `<name>.txt`
/// with the app's accessibility tree.
final class DevScreenshot: ScenarioTestCase {
  @MainActor
  func testScreen() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let scenario = environment["SCREENSHOTS_SCENARIO"],
      let output = environment["SCREENSHOTS_OUTPUT"],
      let receipt = environment["SCREENSHOTS_RECEIPT"]
    else { throw XCTSkip("Run through make screenshot.") }

    let name = environment["SCREENSHOTS_NAME"].flatMap { $0.isEmpty ? nil : $0 } ?? scenario
    let directory = URL(filePath: output, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let previous =
      Appearance.allCases.map { "\(name)-\($0.rawValue).png" }
      + ["\(name).txt", "\(name)-failure.png", "\(name)-failure.txt"]
    for file in previous {
      try? FileManager.default.removeItem(at: directory.appending(path: file))
    }
    let appearances = try Self.appearances(environment["SCREENSHOTS_APPEARANCE"] ?? "")

    let highlights = directory.appending(path: ".\(name).highlights.json")
    let textSize = environment["SCREENSHOTS_TEXT_SIZE"].flatMap { $0.isEmpty ? nil : $0 }
    let app = launch(
      scenario: scenario, receipt: receipt, highlights: highlights, appearance: appearances[0],
      arguments: textSize.map { ["-ScreenshotTextSize", $0] } ?? [])
    defer {
      app.terminate()
      try? FileManager.default.removeItem(at: highlights)
    }

    for appearance in appearances {
      XCUIDevice.shared.appearance = appearance.deviceAppearance
      do {
        try waitForHighlight(Self.readyHighlight)
      } catch {
        try writeFailure(of: app, named: name, to: directory)
        throw error
      }
      settle(for: 1)
      try XCUIScreen.main.screenshot().pngRepresentation.write(
        to: directory.appending(path: "\(name)-\(appearance.rawValue).png"))
    }
    try Data(app.debugDescription.utf8).write(to: directory.appending(path: "\(name).txt"))
  }

  private static func appearances(_ argument: String) throws -> [Appearance] {
    if argument.isEmpty { return [.light] }
    if argument == "both" { return Appearance.allCases }
    guard let appearance = Appearance(rawValue: argument) else {
      throw CaptureError.unknownAppearance(argument)
    }
    return [appearance]
  }
}
