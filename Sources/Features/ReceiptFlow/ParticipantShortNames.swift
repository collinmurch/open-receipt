import Foundation

enum ParticipantShortNames {
  /// Returns each participant's first name, adding as many leading letters of the last name as
  /// needed to tell apart participants who share a first name.
  static func names(for participants: [ReceiptParticipant]) -> [ReceiptParticipant.ID: String] {
    let parts = participants.map { (id: $0.id, name: NameParts($0.displayName)) }
    let groups = Dictionary(grouping: parts) { $0.name.first.lowercased() }

    var result: [ReceiptParticipant.ID: String] = [:]
    for group in groups.values {
      for entry in group {
        let others = group.filter { $0.id != entry.id }.map(\.name.last)
        result[entry.id] = entry.name.shortName(distinctFrom: others)
      }
    }
    return result
  }
}

private struct NameParts {
  let first: String
  let last: String

  init(_ displayName: String) {
    let words = displayName.split(whereSeparator: \.isWhitespace)
    first = words.first.map(String.init) ?? ""
    last = words.dropFirst().joined(separator: " ")
  }

  func shortName(distinctFrom otherLastNames: [String]) -> String {
    guard !otherLastNames.isEmpty, !last.isEmpty else { return first }

    for length in 1..<last.count {
      let prefix = last.prefix(length).lowercased()
      if prefix.last?.isWhitespace == true { continue }
      if !otherLastNames.contains(where: { $0.prefix(length).lowercased() == prefix }) {
        return "\(first) \(last.prefix(length))."
      }
    }
    return "\(first) \(last)"
  }
}
