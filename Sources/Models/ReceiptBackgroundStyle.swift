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
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      primary: try container.decode(ReceiptThemeColor.self, forKey: .primary),
      secondary: try container.decode(ReceiptThemeColor.self, forKey: .secondary))
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
