import Foundation
import ReceiptKit

struct FixtureRunResult {
  let label: String
  let sourceURL: URL
  let pages: Int
  let receipt: ParsedReceipt?
  let evaluation: FixtureEvaluation?
  let parseError: String?
  let durationSeconds: Double
  let wasCached: Bool
}

struct ReceiptLabReport {
  let inputPath: String
  let fixtures: [FixtureRunResult]
}

enum ReceiptLabRunnerError: Error, LocalizedError {
  case noInputs(String)

  var errorDescription: String? {
    switch self {
    case .noInputs(let path): "No supported receipts found at \(path)"
    }
  }
}

struct ReceiptLabRunner {
  let cacheDirectory: URL
  let cachedOnly: Bool
  let configuration: ReceiptParserConfiguration
  let respond: ReceiptModelClient.Respond

  func run(
    at url: URL,
    onFixture: ((FixtureRunResult, Int, Int) -> Void)? = nil
  ) async throws -> ReceiptLabReport {
    let fixtures = try resolveFixtures(at: url)
    guard !fixtures.isEmpty else { throw ReceiptLabRunnerError.noInputs(url.path) }
    var results: [FixtureRunResult] = []
    for (index, fixture) in fixtures.enumerated() {
      let result = await runFixture(fixture)
      results.append(result)
      onFixture?(result, index + 1, fixtures.count)
    }
    return ReceiptLabReport(inputPath: url.path, fixtures: results)
  }

  private struct ResolvedFixture {
    let label: String
    let sourceURL: URL
    /// The fixture's decoded `expected.json`, read once for every sample that shares it.
    let expected: Result<ExpectedReceipt, any Error>?
  }

  private func resolveFixtures(at url: URL) throws -> [ResolvedFixture] {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      throw ReceiptInputLoader.LoadError.fileNotFound(url)
    }
    if !isDirectory.boolValue { return [fileFixture(at: url)] }

    if let samples = fixtureSamples(in: url) {
      return resolve(samples, in: url)
    }
    if url.lastPathComponent == "fixtures", let samples = supportedChildren(in: url) {
      return resolve(samples, in: url.deletingLastPathComponent())
    }

    let children = try FileManager.default.contentsOfDirectory(
      at: url, includingPropertiesForKeys: nil
    ).sorted { $0.lastPathComponent < $1.lastPathComponent }
    var fixtures: [ResolvedFixture] = []
    for child in children {
      var childIsDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: child.path, isDirectory: &childIsDirectory)
      else {
        continue
      }
      if childIsDirectory.boolValue {
        fixtures.append(contentsOf: (try? resolveFixtures(at: child)) ?? [])
      } else if ReceiptInputLoader.isSupported(child) {
        fixtures.append(fileFixture(at: child))
      }
    }
    return fixtures
  }

  private func fileFixture(at url: URL) -> ResolvedFixture {
    let parent = url.deletingLastPathComponent()
    if parent.lastPathComponent == "fixtures" {
      let group = parent.deletingLastPathComponent()
      return sample(url, in: group, expected: expectedReceipt(in: group))
    }
    return ResolvedFixture(label: url.lastPathComponent, sourceURL: url, expected: nil)
  }

  /// The samples of the fixture in `group`, which all share its `expected.json`.
  private func resolve(_ samples: [URL], in group: URL) -> [ResolvedFixture] {
    let expected = expectedReceipt(in: group)
    return samples.map { sample($0, in: group, expected: expected) }
  }

  private func sample(
    _ url: URL,
    in group: URL,
    expected: Result<ExpectedReceipt, any Error>?
  ) -> ResolvedFixture {
    ResolvedFixture(
      label: "\(group.lastPathComponent)/\(url.deletingPathExtension().lastPathComponent)",
      sourceURL: url,
      expected: expected)
  }

  private func fixtureSamples(in folder: URL) -> [URL]? {
    let fixtures = folder.appending(path: "fixtures", directoryHint: .isDirectory)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: fixtures.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return nil }
    return supportedChildren(in: fixtures)
  }

  private func supportedChildren(in folder: URL) -> [URL]? {
    guard
      let contents = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
    else { return nil }
    let supported = contents.filter(ReceiptInputLoader.isSupported)
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    return supported.isEmpty ? nil : supported
  }

  private func expectedReceipt(in folder: URL) -> Result<ExpectedReceipt, any Error>? {
    let url = folder.appending(path: "expected.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return Result { try JSONDecoder().decode(ExpectedReceipt.self, from: Data(contentsOf: url)) }
  }

  private func runFixture(_ fixture: ResolvedFixture) async -> FixtureRunResult {
    do {
      let pages = try ReceiptInputLoader.loadFile(fixture.sourceURL)
      let response = try await ReceiptModelClient.response(
        pages: pages,
        cacheDirectory: cacheDirectory,
        cachedOnly: cachedOnly,
        configuration: configuration,
        respond: respond)
      let receipt = try ReceiptModelContract.receipt(from: response.content)
      let evaluation = try evaluationResult(for: receipt, fixture: fixture)
      return FixtureRunResult(
        label: fixture.label,
        sourceURL: fixture.sourceURL,
        pages: pages.count,
        receipt: receipt,
        evaluation: evaluation,
        parseError: nil,
        durationSeconds: response.durationSeconds,
        wasCached: response.wasCached)
    } catch {
      return FixtureRunResult(
        label: fixture.label,
        sourceURL: fixture.sourceURL,
        pages: 0,
        receipt: nil,
        evaluation: nil,
        parseError: error.localizedDescription,
        durationSeconds: 0,
        wasCached: cachedOnly)
    }
  }

  private func evaluationResult(
    for receipt: ParsedReceipt,
    fixture: ResolvedFixture
  ) throws -> FixtureEvaluation? {
    guard let expected = try fixture.expected?.get() else { return nil }
    return FixtureEvaluator.evaluate(actual: receipt, expected: expected)
  }
}
