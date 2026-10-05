import SwiftUI

extension ReceiptBackgroundStyle {
  func accentColor(for colorScheme: ColorScheme) -> Color {
    primary.accentColor(for: colorScheme)
  }

  func colors(for colorScheme: ColorScheme) -> [Color] {
    [primary.backgroundColor(for: colorScheme), secondary.backgroundColor(for: colorScheme)]
  }

  /// A darker accent that stays legible under white labels, for prominent tinted controls.
  var prominentColor: Color {
    primary.accentColor(for: .light)
  }
}

extension ReceiptThemeColor {
  func accentColor(for colorScheme: ColorScheme) -> Color {
    let isDark = colorScheme == .dark
    return switch self {
    case .blue:
      isDark ? Color(red: 0.22, green: 0.72, blue: 1) : Color(red: 0.05, green: 0.42, blue: 0.82)
    case .mint:
      isDark ? Color(red: 0.24, green: 0.86, blue: 0.68) : Color(red: 0, green: 0.48, blue: 0.36)
    case .peach:
      isDark ? Color(red: 1, green: 0.56, blue: 0.36) : Color(red: 0.82, green: 0.30, blue: 0.22)
    case .violet:
      isDark ? Color(red: 0.68, green: 0.56, blue: 1) : Color(red: 0.48, green: 0.30, blue: 0.78)
    case .amber:
      isDark ? Color(red: 1, green: 0.72, blue: 0.2) : Color(red: 0.72, green: 0.43, blue: 0.02)
    case .rose:
      isDark ? Color(red: 1, green: 0.4, blue: 0.62) : Color(red: 0.76, green: 0.18, blue: 0.38)
    case .forest:
      isDark ? Color(red: 0.4, green: 0.82, blue: 0.42) : Color(red: 0.12, green: 0.43, blue: 0.18)
    case .indigo:
      isDark ? Color(red: 0.48, green: 0.58, blue: 1) : Color(red: 0.25, green: 0.28, blue: 0.74)
    }
  }

  func backgroundColor(for colorScheme: ColorScheme) -> Color {
    let isDark = colorScheme == .dark
    return switch self {
    case .blue:
      isDark ? Color(red: 0.05, green: 0.13, blue: 0.28) : Color(red: 0.78, green: 0.9, blue: 1)
    case .mint:
      isDark ? Color(red: 0.03, green: 0.22, blue: 0.16) : Color(red: 0.76, green: 0.96, blue: 0.87)
    case .peach:
      isDark ? Color(red: 0.32, green: 0.12, blue: 0.06) : Color(red: 1, green: 0.82, blue: 0.7)
    case .violet:
      isDark ? Color(red: 0.18, green: 0.08, blue: 0.32) : Color(red: 0.85, green: 0.79, blue: 1)
    case .amber:
      isDark ? Color(red: 0.3, green: 0.2, blue: 0.03) : Color(red: 1, green: 0.9, blue: 0.58)
    case .rose:
      isDark ? Color(red: 0.3, green: 0.07, blue: 0.14) : Color(red: 1, green: 0.76, blue: 0.84)
    case .forest:
      isDark ? Color(red: 0.04, green: 0.18, blue: 0.08) : Color(red: 0.74, green: 0.91, blue: 0.72)
    case .indigo:
      isDark ? Color(red: 0.08, green: 0.09, blue: 0.3) : Color(red: 0.78, green: 0.82, blue: 1)
    }
  }

  var paletteIndex: Int {
    ReceiptThemeColor.allCases.firstIndex(of: self) ?? 0
  }
}
