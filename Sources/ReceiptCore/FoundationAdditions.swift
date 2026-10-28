import Foundation

nonisolated extension StringProtocol {
  /// The text without surrounding whitespace and newlines.
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
