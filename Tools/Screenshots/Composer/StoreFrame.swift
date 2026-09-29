import SwiftUI

enum StoreAppearance: String, CaseIterable {
  case light
  case dark
}

/// One App Store screenshot: a softened photo, a headline, the captured screen as a floating
/// card, and one element of that screen lifted above it.
struct StoreFrame: View {
  static let size = CGSize(width: 1284, height: 2778)

  let shot: StoreShot
  let capture: Capture
  let backdrop: CGImage
  /// The receipt wash's colors, sampled down its leading and trailing edges.
  let swatches: (leading: [Swatch], trailing: [Swatch])
  let appearance: StoreAppearance

  private let maxCardWidth: CGFloat = 1110
  private let cardTop: CGFloat = 500
  private let cardBottomMargin: CGFloat = 64
  private let cardCornerRadius: CGFloat = 68
  private let liftScale: CGFloat = 1.12

  var body: some View {
    ZStack(alignment: .topLeading) {
      backdropLayer
      headline
      card
      lifted
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .environment(\.colorScheme, appearance == .dark ? .dark : .light)
  }

  /// The whole screen fits on the card, so its bottom controls keep their safe-area gap.
  private var cardScale: CGFloat {
    let content = capture.contentRect
    return min(
      maxCardWidth / content.width,
      (Self.size.height - cardTop - cardBottomMargin) / content.height)
  }

  private var cardWidth: CGFloat {
    capture.contentRect.width * cardScale
  }

  private var cardLeading: CGFloat {
    (Self.size.width - cardWidth) / 2
  }

  private var backdropLayer: some View {
    ZStack {
      MeshGradient(
        width: 3, height: 3,
        points: [
          [0, 0], [0.5, 0], [1, 0],
          [0, 0.5], [0.5, 0.5], [1, 0.5],
          [0, 1], [0.5, 1], [1, 1],
        ],
        colors: meshColors)
      Image(decorative: backdrop, scale: 1)
        .resizable()
        .scaledToFill()
        .frame(width: Self.size.width, height: Self.size.height)
        .scaleEffect(1.4)
        .blur(radius: 48)
        .grayscale(1)
        .blendMode(.softLight)
        .opacity(0.2)
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .clipped()
  }

  /// The wash's colors, lightened toward white in light appearance and deepened in dark, most
  /// strongly behind the headline.
  private var meshColors: [Color] {
    let (target, amounts) =
      appearance == .dark ? (Swatch.black, [0.45, 0.3, 0.2]) : (Swatch.white, [0.75, 0.62, 0.5])
    return zip(swatches.leading, swatches.trailing).enumerated().flatMap { row, pair in
      let (leading, trailing) = pair
      return [leading, leading.mixed(with: trailing, by: 0.5), trailing].map { swatch in
        let color = swatch.mixed(with: target, by: amounts[min(row, amounts.count - 1)])
        return Color(red: color.red, green: color.green, blue: color.blue)
      }
    }
  }

  private var headline: some View {
    Text(shot.headline)
      .font(.system(size: 88, weight: .bold))
      .kerning(-1.5)
      .lineSpacing(4)
      .multilineTextAlignment(.center)
      .foregroundStyle(
        appearance == .dark ? Color.white : Color(white: 0.1)
      )
      .frame(width: Self.size.width, height: cardTop - 60)
      .offset(y: 20)
  }

  @ViewBuilder
  private var card: some View {
    let content = capture.contentRect
    if let image = try? capture.crop(content) {
      Image(decorative: image, scale: 1)
        .resizable()
        .frame(width: cardWidth, height: content.height * cardScale)
        .clipShape(.rect(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(appearance == .dark ? 0.14 : 0.5), lineWidth: 2)
        }
        .shadow(color: .black.opacity(appearance == .dark ? 0.55 : 0.22), radius: 60, y: 30)
        .offset(x: cardLeading, y: cardTop)
    }
  }

  /// The highlighted element, drawn larger and above the card from the same pixels.
  @ViewBuilder
  private var lifted: some View {
    if let rect = try? capture.highlightRect(shot.highlight, outset: shot.highlightOutset),
      let image = try? capture.crop(rect)
    {
      let scale = cardScale * liftScale
      let size = CGSize(width: rect.width * scale, height: rect.height * scale)
      let center = CGPoint(
        x: cardLeading + (rect.midX - capture.contentRect.minX) * cardScale,
        y: cardTop + (rect.midY - capture.contentRect.minY) * cardScale)
      let radius =
        shot.highlightCornerRadius.map { $0 * capture.manifest.scale * scale } ?? size.height / 2
      Image(decorative: image, scale: 1)
        .resizable()
        .frame(width: size.width, height: size.height)
        .background(appearance == .dark ? Color(white: 0.12) : Color.white)
        .clipShape(.rect(cornerRadius: radius, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(.white.opacity(appearance == .dark ? 0.18 : 0.7), lineWidth: 2)
        }
        .shadow(color: .black.opacity(appearance == .dark ? 0.6 : 0.28), radius: 48, y: 24)
        .offset(x: center.x - size.width / 2, y: center.y - size.height / 2)
    }
  }
}
