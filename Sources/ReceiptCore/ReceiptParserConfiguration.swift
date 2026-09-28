import Foundation

/// Generation settings for a receipt request. `standard` is what the app ships; the harness can
/// vary these to measure their effect on accuracy and latency.
public struct ReceiptParserConfiguration: Sendable, Equatable {
  public enum ReasoningLevel: String, Sendable, CaseIterable {
    case light
    case moderate
    case deep
  }

  public var reasoningLevel: ReasoningLevel
  /// The longest side, in pixels, that page images are scaled down to before they are sent.
  /// `nil` sends pages at their captured size.
  public var maxPixelDimension: Int?

  public init(reasoningLevel: ReasoningLevel = .moderate, maxPixelDimension: Int? = nil) {
    self.reasoningLevel = reasoningLevel
    self.maxPixelDimension = maxPixelDimension
  }

  public static let standard = ReceiptParserConfiguration()

  /// A stable description of the settings that differ from `standard`, or `nil` when none do.
  public var variantDescription: String? {
    var parts: [String] = []
    if reasoningLevel != Self.standard.reasoningLevel {
      parts.append("reasoning=\(reasoningLevel.rawValue)")
    }
    if maxPixelDimension != Self.standard.maxPixelDimension, let maxPixelDimension {
      parts.append("max-pixels=\(maxPixelDimension)")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " ")
  }
}

/// Whether receipt reading can run right now, for showing persistent status before a scan.
public enum ReceiptModelStatus: Sendable, Equatable {
  case available
  case approachingLimit(canIncreaseLimit: Bool)
  case limitReached(resetDate: Date?, canIncreaseLimit: Bool)
  case unavailable(String)
}
