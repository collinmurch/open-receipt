import SwiftUI

extension PaymentMethod {
  func color(for colorScheme: ColorScheme) -> Color {
    switch self {
    case .venmo:
      Color(red: 0, green: 140.0 / 255.0, blue: 1)
    case .cashApp:
      Color(red: 0, green: 214.0 / 255.0, blue: 79.0 / 255.0)
    case .iMessage:
      colorScheme == .dark ? .white : .black
    case .none:
      .orange
    }
  }
}

struct PaymentMethodIcon: View {
  let method: PaymentMethod

  @ScaledMetric(relativeTo: .body) private var size = 29

  var body: some View {
    Group {
      if let assetName = method.iconAssetName {
        Image(assetName)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: "nosign")
          .font(.system(size: size * 0.55, weight: .semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.gray, in: .rect(cornerRadius: size * 0.22))
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
