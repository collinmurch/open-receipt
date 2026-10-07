import CoreGraphics
import SwiftUI

/// The App Store header: everyone's breakdown slip, drawn by the app itself, fanned out like a
/// hand of cards over the teal wash.
struct HeaderArtwork: View {
  static let size = CGSize(width: 3840, height: 1646)

  /// The people's slips, left to right. The middle one is drawn in front.
  let slips: [CGImage]

  /// Pixels per point of the slips on the canvas. The app writes them at 4x.
  private let slipScale: CGFloat = 0.52
  private let spread: CGFloat = 700
  private let tilt: Double = 6
  /// The outer slips' size beside the middle one's, so they sit a little farther back.
  private let outerScale: CGFloat = 0.95

  var body: some View {
    ZStack(alignment: .topLeading) {
      ArtworkBackdrop(size: Self.size, slips: Self.drifting)
      ForEach(drawingOrder, id: \.self) { index in
        slip(at: index)
      }
    }
    .frame(width: Self.size.width, height: Self.size.height)
  }

  /// Outer slips first, so each one overlaps the one beside it toward the middle.
  private var drawingOrder: [Int] {
    let middle = Double(slips.count - 1) / 2
    return slips.indices.sorted { abs(Double($0) - middle) > abs(Double($1) - middle) }
  }

  private func slip(at index: Int) -> some View {
    let image = slips[index]
    let middle = CGFloat(slips.count - 1) / 2
    let offset = CGFloat(index) - middle
    let isOuter = offset != 0
    let scale = slipScale * (isOuter ? outerScale : 1)
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    let top: CGFloat = isOuter ? 250 : 170
    return Image(decorative: image, scale: 1)
      .resizable()
      .interpolation(.high)
      .frame(width: size.width, height: size.height)
      .shadow(color: ArtworkPalette.ink.opacity(0.14), radius: 4, y: 3)
      .shadow(
        color: ArtworkPalette.ink.opacity(isOuter ? 0.2 : 0.3),
        radius: isOuter ? 40 : 64,
        y: isOuter ? 28 : 44)
      .rotationEffect(.degrees(Double(offset) * tilt), anchor: .bottom)
      .position(x: Self.size.width / 2 + offset * spread, y: top + size.height / 2)
  }

  private static let drifting = [
    DriftingSlip(center: CGPoint(x: 330, y: 1150), width: 430, height: 780, angle: -14, depth: 0.55),
    DriftingSlip(center: CGPoint(x: 820, y: 230), width: 300, height: 520, angle: 9, depth: 0.9),
    DriftingSlip(center: CGPoint(x: 3480, y: 360), width: 380, height: 700, angle: 12, depth: 0.6),
    DriftingSlip(center: CGPoint(x: 3120, y: 1420), width: 300, height: 540, angle: -7, depth: 0.95),
    DriftingSlip(center: CGPoint(x: 3760, y: 1350), width: 260, height: 460, angle: 18, depth: 0.3),
    DriftingSlip(center: CGPoint(x: 90, y: 300), width: 240, height: 420, angle: 6, depth: 0.25),
  ]
}
