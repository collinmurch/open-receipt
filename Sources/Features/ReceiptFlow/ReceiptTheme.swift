import Foundation

enum ReceiptThemeColor: String, CaseIterable, Codable, Equatable, Sendable {
  case blue
  case mint
  case peach
  case violet
  case amber
  case rose
  case forest
  case indigo
}

struct ReceiptBackgroundStyle: Codable, Equatable, Sendable {
  let primary: ReceiptThemeColor
  let secondary: ReceiptThemeColor

  static let blue = ReceiptBackgroundStyle(primary: .blue, secondary: .violet)
  static let mint = ReceiptBackgroundStyle(primary: .mint, secondary: .blue)
  static let peach = ReceiptBackgroundStyle(primary: .peach, secondary: .rose)
  static let violet = ReceiptBackgroundStyle(primary: .violet, secondary: .mint)

  static func random() -> Self {
    let primary = ReceiptThemeColor.allCases.randomElement() ?? .blue
    let secondary = primary.partnerColors.randomElement() ?? .violet
    return ReceiptBackgroundStyle(primary: primary, secondary: secondary)
  }

  init(primary: ReceiptThemeColor, secondary: ReceiptThemeColor) {
    self.primary = primary
    self.secondary = primary == secondary ? primary.partnerColors[0] : secondary
  }

  init(from decoder: Decoder) throws {
    if let value = try? decoder.singleValueContainer().decode(String.self) {
      self =
        switch value {
        case "blue": .blue
        case "mint": .mint
        case "peach": .peach
        case "violet": .violet
        default:
          throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unknown receipt color style."))
        }
      return
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      primary: try container.decode(ReceiptThemeColor.self, forKey: .primary),
      secondary: try container.decode(ReceiptThemeColor.self, forKey: .secondary))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(primary, forKey: .primary)
    try container.encode(secondary, forKey: .secondary)
  }

  private enum CodingKeys: String, CodingKey {
    case primary
    case secondary
  }
}

extension ReceiptThemeColor {
  fileprivate var partnerColors: [ReceiptThemeColor] {
    switch self {
    case .blue: [.amber, .rose, .peach, .mint]
    case .mint: [.violet, .rose, .amber, .indigo]
    case .peach: [.blue, .forest, .indigo, .violet]
    case .violet: [.amber, .mint, .peach, .forest]
    case .amber: [.blue, .violet, .indigo, .mint]
    case .rose: [.mint, .blue, .forest, .indigo]
    case .forest: [.peach, .violet, .rose, .amber]
    case .indigo: [.peach, .amber, .mint, .rose]
    }
  }
}
