import Foundation
import ReceiptKit

@main
struct ReceiptLab {
  static func main() async {
    var args = Array(CommandLine.arguments.dropFirst())
    guard args.first == "run" else {
      printUsage()
      exit(args.first == "help" || args.first == "--help" ? 0 : 64)
    }
    args.removeFirst()
    await run(args)
  }

  private static func run(_ rawArgs: [String]) async {
    var format: ReportFormat = .text
    var cache = ".build/receiptlab-cache"
    var cachedOnly = false
    var quiet = false
    var configuration = ReceiptParserConfiguration.standard
    var positional: [String] = []
    var iterator = rawArgs.makeIterator()
    while let argument = iterator.next() {
      switch argument {
      case "--format": format = parseFormat(iterator.next())
      case "--cache": cache = required(iterator.next(), flag: "--cache")
      case "--cached": cachedOnly = true
      case "--quiet": quiet = true
      case "--reasoning": configuration.reasoningLevel = parseReasoning(iterator.next())
      case "--max-pixels": configuration.maxPixelDimension = parsePixels(iterator.next())
      default: positional.append(argument)
      }
    }
    guard positional.count == 1 else {
      printUsage()
      exit(64)
    }

    let inputURL = URL(filePath: positional[0])
    let runner = ReceiptLabRunner(
      cacheDirectory: URL(filePath: cache, directoryHint: .isDirectory),
      cachedOnly: cachedOnly,
      configuration: configuration,
      respond: ReceiptModelClient.privateCloudCompute(configuration: configuration))
    if format == .text && !quiet {
      write(
        ReceiptLabReporter.streamHeader(
          inputPath: inputURL.path, variant: configuration.variantDescription))
    }
    do {
      let report = try await runner.run(at: inputURL) { fixture, index, total in
        if format == .text && !quiet {
          write(ReceiptLabReporter.streamFixture(fixture, index: index, total: total))
        } else if format == .summary && !quiet {
          write(ReceiptLabReporter.streamSummaryFixture(fixture))
        }
      }
      if format != .json && !quiet {
        write(ReceiptLabReporter.streamSummary(report))
      } else {
        let output = ReceiptLabReporter.render(report, format: format)
        write(output)
        if !output.hasSuffix("\n") { write("\n") }
      }
      if report.fixtures.contains(where: { $0.parseError != nil || $0.evaluation?.passed == false })
      {
        exit(1)
      }
    } catch {
      FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
      exit(1)
    }
  }

  private static func parseFormat(_ raw: String?) -> ReportFormat {
    guard let raw, let format = ReportFormat(raw) else {
      usageError("Invalid/missing value for --format")
    }
    return format
  }

  private static func parseReasoning(_ raw: String?) -> ReceiptParserConfiguration.ReasoningLevel {
    guard let raw, let level = ReceiptParserConfiguration.ReasoningLevel(rawValue: raw) else {
      usageError("Invalid/missing value for --reasoning (\(reasoningLevels(separator: ", ")))")
    }
    return level
  }

  private static func parsePixels(_ raw: String?) -> Int {
    guard let raw, let pixels = Int(raw), pixels > 0 else {
      usageError("Invalid/missing value for --max-pixels")
    }
    return pixels
  }

  private static func required(_ raw: String?, flag: String) -> String {
    guard let raw, !raw.isEmpty else {
      usageError("Missing value for \(flag)")
    }
    return raw
  }

  private static func reasoningLevels(separator: String) -> String {
    ReceiptParserConfiguration.ReasoningLevel.allCases.map(\.rawValue).joined(separator: separator)
  }

  private static func usageError(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(64)
  }

  private static func write(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
  }

  private static func printUsage() {
    let text = """
      ReceiptLab — multimodal receipt evaluation

      USAGE
        ReceiptLab run <path> [--format text|json|summary] [--cached] [--quiet]
                       [--reasoning \(reasoningLevels(separator: "|"))] [--max-pixels N]

      Prefer `make receipts` over invoking this binary directly.
      """
    write(text + "\n")
  }
}
