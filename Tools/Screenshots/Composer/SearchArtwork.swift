import CoreGraphics
import SwiftUI

/// The App Store search result: the receipt photo under a scanning beam beside the app reading
/// it, its status lifted between them, over the teal wash.
struct SearchArtwork: View {
  static let size = CGSize(width: 3840, height: 2560)
  static let headline = "Scan a receipt. Watch every line appear."

  let capture: Capture
  let photo: CGImage
  /// The part of the photo the camera shows, in its pixels: the receipt from its header down to
  /// the tip suggestions, above the line with the restaurant's email address.
  var photoCrop = CGRect(x: 70, y: 150, width: 610, height: 760)
  /// Where the beam crosses the photo, in its pixels: the line being written on the reading
  /// screen.
  var beamY: CGFloat = 505

  private let top: CGFloat = 660
  private let cameraFrame = CGRect(x: 640, y: 780, width: 1100, height: 1370)
  private let screenLeading: CGFloat = 1900
  private let screenWidth: CGFloat = 1300
  private let cornerRadius: CGFloat = 84
  private let liftScale: CGFloat = 1.1

  var body: some View {
    ZStack(alignment: .topLeading) {
      ArtworkBackdrop(size: Self.size, slips: Self.drifting)
      headline
      camera
      screen
      lifted
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .environment(\.colorScheme, .light)
  }

  private var headline: some View {
    Text(Self.headline)
      .font(.system(size: 150, weight: .bold))
      .kerning(-3)
      .foregroundStyle(ArtworkPalette.ink)
      .frame(width: Self.size.width, height: top - 40)
  }

  @ViewBuilder
  private var camera: some View {
    if let cropped = photo.cropping(to: photoCrop) {
      let scale = cameraFrame.width / photoCrop.width
      let beam = (beamY - photoCrop.minY) * scale
      ZStack(alignment: .topLeading) {
        Image(decorative: cropped, scale: 1)
          .resizable()
          .interpolation(.high)
          .frame(width: cameraFrame.width, height: photoCrop.height * scale)
        ArtworkPalette.mint
          .frame(height: beam)
          .blendMode(.multiply)
        LinearGradient(
          colors: [ArtworkPalette.mist.opacity(0), ArtworkPalette.mist.opacity(0.6)],
          startPoint: .top, endPoint: .bottom
        )
        .frame(height: 300)
        .offset(y: beam - 300)
        .blendMode(.screen)
        beamLine
          .offset(y: beam - 40)
        brackets
      }
      .frame(width: cameraFrame.width, height: cameraFrame.height, alignment: .top)
      .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(.white.opacity(0.55), lineWidth: 3)
      }
      .shadow(color: ArtworkPalette.ink.opacity(0.16), radius: 6, y: 4)
      .shadow(color: ArtworkPalette.ink.opacity(0.3), radius: 70, y: 44)
      // The receipt leans left in the photo, so leaning the card right levels its text.
      .rotationEffect(.degrees(3))
      .position(x: cameraFrame.midX, y: cameraFrame.midY)
    }
  }

  /// A bright line with a soft halo, 80 points tall so the halo isn't clipped.
  private var beamLine: some View {
    ZStack {
      Capsule()
        .fill(ArtworkPalette.teal.opacity(0.7))
        .frame(height: 26)
        .blur(radius: 16)
      Capsule()
        .fill(.white)
        .frame(height: 7)
        .padding(.horizontal, 40)
    }
    .frame(width: cameraFrame.width, height: 80)
  }

  private var brackets: some View {
    let inset: CGFloat = 64
    let arm: CGFloat = 120
    return Path { path in
      let rect = CGRect(origin: .zero, size: cameraFrame.size).insetBy(dx: inset, dy: inset)
      for corner in [
        (rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1.0, 1.0),
        (rect.minX, rect.maxY, 1.0, -1.0), (rect.maxX, rect.maxY, -1.0, -1.0),
      ] {
        let (x, y, dx, dy) = corner
        path.move(to: CGPoint(x: x, y: y + arm * dy))
        path.addLine(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x + arm * dx, y: y))
      }
    }
    .stroke(.white, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
    .shadow(color: .black.opacity(0.25), radius: 12)
  }

  private var screenScale: CGFloat {
    screenWidth / capture.contentRect.width
  }

  @ViewBuilder
  private var screen: some View {
    // The screen runs off the bottom edge, so only the part that shows is drawn.
    let content = capture.contentRect
    let visible = min(content.height, ((Self.size.height - top) / screenScale + 40).rounded())
    if let image = try? capture.crop(
      CGRect(x: content.minX, y: content.minY, width: content.width, height: visible))
    {
      Image(decorative: image, scale: 1)
        .resizable()
        .interpolation(.high)
        .frame(width: screenWidth, height: visible * screenScale)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.6), lineWidth: 3)
        }
        .shadow(color: ArtworkPalette.ink.opacity(0.16), radius: 6, y: 4)
        .shadow(color: ArtworkPalette.ink.opacity(0.32), radius: 80, y: 50)
        .offset(x: screenLeading, y: top)
    }
  }

  /// The reading status, larger and above the screen, from the same pixels.
  @ViewBuilder
  private var lifted: some View {
    if let rect = try? capture.highlightRect("receipt-reading-status"),
      let image = try? capture.crop(rect)
    {
      let scale = screenScale * liftScale
      let size = CGSize(width: rect.width * scale, height: rect.height * scale)
      let center = CGPoint(
        x: screenLeading + (rect.midX - capture.contentRect.minX) * screenScale,
        y: top + (rect.midY - capture.contentRect.minY) * screenScale)
      let radius = 22 * capture.manifest.scale * scale
      Image(decorative: image, scale: 1)
        .resizable()
        .interpolation(.high)
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: radius, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(.white.opacity(0.75), lineWidth: 3)
        }
        .shadow(color: ArtworkPalette.ink.opacity(0.18), radius: 6, y: 4)
        .shadow(color: ArtworkPalette.ink.opacity(0.32), radius: 56, y: 32)
        .position(center)
    }
  }

  private static let drifting = [
    DriftingSlip(center: CGPoint(x: 260, y: 1900), width: 520, height: 940, angle: -12, depth: 0.5),
    DriftingSlip(center: CGPoint(x: 300, y: 520), width: 320, height: 580, angle: 10, depth: 0.9),
    DriftingSlip(center: CGPoint(x: 3560, y: 700), width: 420, height: 760, angle: 13, depth: 0.55),
    DriftingSlip(center: CGPoint(x: 3640, y: 2150), width: 360, height: 640, angle: -8, depth: 0.85),
    DriftingSlip(center: CGPoint(x: 1700, y: 120), width: 260, height: 460, angle: -6, depth: 1),
  ]
}
