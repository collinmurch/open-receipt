import CoreGraphics
import SwiftUI

/// The colors of the header and search artwork, taken from the app icon's teal.
enum ArtworkPalette {
  static let mist = Color(red: 0.89, green: 0.96, blue: 0.89)
  static let mint = Color(red: 0.79, green: 0.91, blue: 0.81)
  static let sage = Color(red: 0.62, green: 0.82, blue: 0.76)
  static let teal = Color(red: 0.31, green: 0.58, blue: 0.60)
  static let deep = Color(red: 0.18, green: 0.43, blue: 0.46)
  /// Text and shadows, a teal so dark it reads as ink.
  static let ink = Color(red: 0.04, green: 0.17, blue: 0.17)
  static let paper = Color(red: 1, green: 0.995, blue: 0.984)
}

/// A slip of blank receipt paper drifting behind the artwork. `depth` runs from 0, nearest and
/// sharpest, to 1, farthest and softest.
struct DriftingSlip {
  let center: CGPoint
  let width: CGFloat
  let height: CGFloat
  let angle: Double
  let depth: Double
}

/// A wash in the app icon's teal with slips of receipt paper drifting through it at a few
/// depths, and a fine grain so the gradient doesn't band.
struct ArtworkBackdrop: View {
  let size: CGSize
  let slips: [DriftingSlip]

  var body: some View {
    ZStack(alignment: .topLeading) {
      MeshGradient(
        width: 3, height: 3,
        points: [
          [0, 0], [0.55, 0], [1, 0],
          [0, 0.5], [0.42, 0.55], [1, 0.45],
          [0, 1], [0.5, 1], [1, 1],
        ],
        colors: [
          ArtworkPalette.mist, ArtworkPalette.mint, ArtworkPalette.sage,
          ArtworkPalette.mint, ArtworkPalette.sage, ArtworkPalette.teal,
          ArtworkPalette.sage, ArtworkPalette.teal, ArtworkPalette.deep,
        ])
      glow(at: CGPoint(x: size.width * 0.5, y: size.height * 0.42), radius: size.height * 0.55,
        color: .white, opacity: 0.32)
      glow(at: CGPoint(x: size.width * 0.08, y: 0), radius: size.height * 0.6,
        color: ArtworkPalette.mist, opacity: 0.7)
      glow(at: CGPoint(x: size.width * 0.95, y: size.height), radius: size.height * 0.7,
        color: ArtworkPalette.deep, opacity: 0.45)
      ForEach(slips.indices, id: \.self) { index in
        slip(slips[index])
      }
      Grain.image
        .resizable(resizingMode: .tile)
        .blendMode(.overlay)
        .opacity(0.5)
    }
    .frame(width: size.width, height: size.height)
    .clipped()
  }

  private func glow(at center: CGPoint, radius: CGFloat, color: Color, opacity: Double)
    -> some View
  {
    RadialGradient(
      colors: [color.opacity(opacity), color.opacity(0)],
      center: UnitPoint(x: center.x / size.width, y: center.y / size.height),
      startRadius: 0,
      endRadius: radius)
  }

  private func slip(_ slip: DriftingSlip) -> some View {
    let lineCount = Int((slip.height - slip.width * 0.35) / (slip.width * 0.11))
    return ZStack(alignment: .top) {
      TornSlipShape(toothWidth: slip.width / 14, cornerRadius: slip.width * 0.06)
        .fill(.white.opacity(0.26 - 0.12 * slip.depth))
      VStack(alignment: .leading, spacing: slip.width * 0.06) {
        Capsule().frame(width: slip.width * 0.42, height: slip.width * 0.05)
        ForEach(0..<max(lineCount, 0), id: \.self) { line in
          HStack {
            Capsule().frame(width: slip.width * [0.46, 0.34, 0.52, 0.28, 0.4][line % 5])
            Spacer()
            Capsule().frame(width: slip.width * 0.14)
          }
          .frame(height: slip.width * 0.035)
        }
      }
      .foregroundStyle(ArtworkPalette.teal.opacity(0.12 - 0.06 * slip.depth))
      .padding(.horizontal, slip.width * 0.12)
      .padding(.top, slip.width * 0.14)
    }
    .frame(width: slip.width, height: slip.height, alignment: .top)
    .clipped()
    .rotationEffect(.degrees(slip.angle))
    .blur(radius: 2 + 26 * slip.depth)
    .position(slip.center)
  }
}

/// Receipt paper: rounded at the top and torn into teeth along the bottom, like the shared
/// breakdown slips.
struct TornSlipShape: Shape {
  var toothWidth: CGFloat = 16
  var cornerRadius: CGFloat = 20

  func path(in rect: CGRect) -> Path {
    let toothHeight = toothWidth / 2
    let toothTop = rect.maxY - toothHeight
    let teeth = max(Int((rect.width / toothWidth).rounded()), 1)
    let width = rect.width / CGFloat(teeth)
    return Path { path in
      path.move(to: CGPoint(x: rect.minX, y: toothTop))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
      path.addArc(
        tangent1End: CGPoint(x: rect.minX, y: rect.minY),
        tangent2End: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
        radius: cornerRadius)
      path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
      path.addArc(
        tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
        tangent2End: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
        radius: cornerRadius)
      path.addLine(to: CGPoint(x: rect.maxX, y: toothTop))
      for tooth in 0..<teeth {
        let right = rect.maxX - CGFloat(tooth) * width
        path.addLine(to: CGPoint(x: right - width / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - width, y: toothTop))
      }
      path.closeSubpath()
    }
  }
}

/// A tile of gray noise, the same on every run so renders only change when the design does.
@MainActor
enum Grain {
  static let image: Image = {
    let side = 256
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    var pixels = [UInt8](repeating: 0, count: side * side)
    for index in pixels.indices {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      pixels[index] = UInt8(108 + (state >> 59))
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let cgImage = CGImage(
      width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return Image(decorative: cgImage, scale: 1)
  }()
}
