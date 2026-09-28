import Darwin
import Foundation
import ReceiptKit

enum ReceiptLabReporter {
  static func render(_ report: ReceiptLabReport, format: ReportFormat) -> String {
    switch format {
    case .text: return renderText(report, color: Color.active)
    case .json: return renderJSON(report)
    case .summary: return renderSummary(report)
    }
  }

  static func renderSummary(_ report: ReceiptLabReport) -> String {
    let color = Color.active
    var out = ""
    var passed = 0
    var failed = 0
    var errored = 0
    for fixture in report.fixtures {
      let badge: String
      if let evaluation = fixture.evaluation {
        if evaluation.passed {
          badge = color.green("PASS")
          passed += 1
        } else {
          badge = color.red("FAIL")
          failed += 1
        }
      } else if fixture.parseError != nil {
        badge = color.yellow("ERR ")
        errored += 1
      } else {
        badge = color.cyan("RAN ")
      }
      let duration = String(format: "%.2fs", fixture.durationSeconds)
      out += "\(badge) \(fixture.label) \(color.dim("(\(duration))"))\n"
    }
    out += color.dim(String(repeating: "─", count: 40)) + "\n"
    out += "\(report.fixtures.count) fixtures  "
    out += "\(color.green("\(passed) pass"))  "
    out += "\(failed > 0 ? color.red("\(failed) fail") : "0 fail")  "
    out += "\(errored > 0 ? color.yellow("\(errored) err") : "0 err")\n"
    return out
  }

  static func streamHeader(inputPath: String, variant: String? = nil) -> String {
    let color = Color.active
    let title =
      variant.map { "ReceiptLab — \(inputPath) (\($0))" }
      ?? "ReceiptLab — \(inputPath)"
    return color.dim(title) + "\n"
      + color.dim(String(repeating: "─", count: 60)) + "\n"
  }

  static func streamFixture(
    _ fixture: FixtureRunResult,
    index: Int,
    total: Int
  ) -> String {
    let color = Color.active
    let progress = color.dim("[\(index)/\(total)]") + " "
    return progress + renderFixtureText(fixture, color: color) + "\n"
  }

  static func streamSummaryFixture(_ fixture: FixtureRunResult) -> String {
    let color = Color.active
    let badge: String
    if let evaluation = fixture.evaluation {
      badge = evaluation.passed ? color.green("PASS") : color.red("FAIL")
    } else if fixture.parseError != nil {
      badge = color.yellow("ERR ")
    } else {
      badge = color.cyan("RAN ")
    }
    let duration = String(format: "%.2fs", fixture.durationSeconds)
    let cache = fixture.wasCached ? ", cached" : ""
    return "\(badge) \(fixture.label) \(color.dim("(\(duration)\(cache))"))\n"
  }

  static func streamSummary(_ report: ReceiptLabReport) -> String {
    let color = Color.active
    var out = color.dim(String(repeating: "─", count: 60)) + "\n"
    out += "Fixtures: \(report.fixtures.count)\n"
    let evaluated = report.fixtures.compactMap { $0.evaluation }
    if !evaluated.isEmpty {
      let passed = evaluated.filter(\.passed).count
      let summary = "Evaluations: \(passed)/\(evaluated.count) passed"
      out += (passed == evaluated.count ? color.green(summary) : color.red(summary)) + "\n"
    }
    let errored = report.fixtures.filter { $0.parseError != nil }.count
    if errored > 0 {
      out += color.yellow("Errors: \(errored)") + "\n"
    }
    return out
  }

  // MARK: - Text

  private static func renderText(_ report: ReceiptLabReport, color: Color) -> String {
    var out = ""
    out += color.dim("ReceiptLab — \(report.inputPath)") + "\n"
    out += color.dim(String(repeating: "─", count: 60)) + "\n"
    for fixture in report.fixtures {
      out += renderFixtureText(fixture, color: color)
      out += "\n"
    }
    out += streamSummary(report)
    return out
  }

  private static func renderFixtureText(_ f: FixtureRunResult, color: Color) -> String {
    var out = ""
    let badge: String
    if let evaluation = f.evaluation {
      badge = evaluation.passed ? color.green("[PASS]") : color.red("[FAIL]")
    } else if f.parseError != nil {
      badge = color.yellow("[ERR ]")
    } else {
      badge = color.cyan("[RAN ]")
    }
    let duration = String(format: "%.2fs", f.durationSeconds)
    let pageWord = f.pages == 1 ? "page" : "pages"
    let cache = f.wasCached ? ", cached" : ""
    out +=
      "\(badge) \(color.bold(f.label))  \(color.dim("(\(duration), \(f.pages) \(pageWord)\(cache))"))\n"

    if let error = f.parseError {
      out += "       \(color.red("error:")) \(error)\n"
      return out
    }

    if let receipt = f.receipt {
      out += "       merchant: \(receipt.merchantName.isEmpty ? "—" : receipt.merchantName)\n"
      out += "       totals:   \(formatTotals(receipt))\n"
      if !receipt.warnings.isEmpty {
        out += "       warnings: \(receipt.warnings.joined(separator: ", "))\n"
      }
    }
    if let evaluation = f.evaluation {
      for check in evaluation.checks {
        out += renderCheckText(check, color: color)
      }
    }
    return out
  }

  private static func renderCheckText(_ check: FixtureEvaluation.Check, color: Color) -> String {
    let tag: String
    switch check.status {
    case .pass: tag = color.green("[PASS]")
    case .fail: tag = color.red("[FAIL]")
    case .skipped: tag = color.dim("[SKIP]")
    }
    let expected = check.expected ?? "—"
    let actual = check.actual ?? "—"
    let detail = check.detail.map { " \(color.dim("(\($0))"))" } ?? ""

    switch check.status {
    case .pass:
      return "       \(tag) \(check.field): \(actual)\n"
    case .skipped:
      return
        "       \(tag) \(color.dim("\(check.field): expected \(expected), actual \(actual)"))\n"
    case .fail:
      return "       \(tag) \(check.field): expected \(expected), actual \(actual)\(detail)\n"
    }
  }

  private static func formatTotals(_ receipt: ParsedReceipt) -> String {
    String(
      format: "currency=%@ subtotal=%.2f tax=%.2f tip=%.2f total=%.2f",
      receipt.currency, receipt.subtotal, receipt.tax, receipt.tip, receipt.total)
  }

  // MARK: - JSON

  private static func renderJSON(_ report: ReceiptLabReport) -> String {
    let payload = JSONReport(
      inputPath: report.inputPath,
      fixtureCount: report.fixtures.count,
      fixtures: report.fixtures.map(JSONFixture.init))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(payload),
      let text = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return text
  }

  private struct JSONReport: Encodable {
    let inputPath: String
    let fixtureCount: Int
    let fixtures: [JSONFixture]
  }

  private struct JSONFixture: Encodable {
    let label: String
    let source: String
    let pages: Int
    let durationSeconds: Double
    let merchantName: String
    let totals: JSONTotals?
    let items: [JSONItem]
    let warnings: [String]
    let parseError: String?
    let evaluation: JSONEvaluation?
    let cached: Bool

    init(_ f: FixtureRunResult) {
      label = f.label
      source = f.sourceURL.path
      pages = f.pages
      durationSeconds = f.durationSeconds
      merchantName = f.receipt?.merchantName ?? ""
      totals = f.receipt.map(JSONTotals.init)
      items = f.receipt?.items.map(JSONItem.init) ?? []
      warnings = f.receipt?.warnings ?? []
      parseError = f.parseError
      evaluation = f.evaluation.map(JSONEvaluation.init)
      cached = f.wasCached
    }
  }

  private struct JSONTotals: Encodable {
    let currency: String
    let subtotal: Double
    let tax: Double
    let tip: Double
    let total: Double
    init(_ receipt: ParsedReceipt) {
      currency = receipt.currency
      subtotal = receipt.subtotal
      tax = receipt.tax
      tip = receipt.tip
      total = receipt.total
    }
  }

  private struct JSONItem: Encodable {
    let description: String
    let quantity: Double
    let lineTotal: Double
    init(_ item: ReceiptItem) {
      description = item.description
      quantity = item.quantity
      lineTotal = item.lineTotal
    }
  }

  private struct JSONEvaluation: Encodable {
    let passed: Bool
    let checks: [JSONCheck]
    init(_ e: FixtureEvaluation) {
      passed = e.passed
      checks = e.checks.map(JSONCheck.init)
    }
  }

  private struct JSONCheck: Encodable {
    let field: String
    let status: String
    let expected: String?
    let actual: String?
    let detail: String?
    init(_ c: FixtureEvaluation.Check) {
      field = c.field
      status = c.status.rawValue
      expected = c.expected
      actual = c.actual
      detail = c.detail
    }
  }
}

// MARK: - ANSI coloring

private struct Color {
  let enabled: Bool

  static let active: Color = {
    let noColor = ProcessInfo.processInfo.environment["NO_COLOR"] != nil
    let isTTY = isatty(fileno(stdout)) != 0
    return Color(enabled: isTTY && !noColor)
  }()

  func wrap(_ text: String, _ code: String) -> String {
    enabled ? "\u{001B}[\(code)m\(text)\u{001B}[0m" : text
  }

  func green(_ text: String) -> String { wrap(text, "32") }
  func red(_ text: String) -> String { wrap(text, "31") }
  func yellow(_ text: String) -> String { wrap(text, "33") }
  func cyan(_ text: String) -> String { wrap(text, "36") }
  func dim(_ text: String) -> String { wrap(text, "2") }
  func bold(_ text: String) -> String { wrap(text, "1") }
}
