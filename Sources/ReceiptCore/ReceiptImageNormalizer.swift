import CoreGraphics
import ImageIO

enum ReceiptImageNormalizer {
  /// Returns an image whose pixels include the supplied display orientation.
  static func normalized(
    _ image: CGImage,
    orientation: CGImagePropertyOrientation
  ) -> CGImage? {
    guard orientation != .up else { return image }

    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let swapsAxes =
      switch orientation {
      case .left, .leftMirrored, .right, .rightMirrored: true
      case .up, .upMirrored, .down, .downMirrored: false
      }
    let outputWidth = swapsAxes ? image.height : image.width
    let outputHeight = swapsAxes ? image.width : image.height
    guard
      let context = CGContext(
        data: nil,
        width: outputWidth,
        height: outputHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    let transform =
      switch orientation {
      case .up:
        CGAffineTransform.identity
      case .upMirrored:
        CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)
      case .down:
        CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
      case .downMirrored:
        CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
      case .leftMirrored:
        CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: height, ty: width)
      case .right:
        CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
      case .rightMirrored:
        CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
      case .left:
        CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
      }

    context.concatenate(transform)
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  /// Returns an image whose longest side is at most `maxPixelDimension`, or `image` itself when
  /// it already fits.
  static func downscaled(_ image: CGImage, maxPixelDimension: Int) -> CGImage? {
    let longestSide = max(image.width, image.height)
    guard maxPixelDimension > 0, longestSide > maxPixelDimension else { return image }

    let scale = Double(maxPixelDimension) / Double(longestSide)
    let width = max(1, Int((Double(image.width) * scale).rounded()))
    let height = max(1, Int((Double(image.height) * scale).rounded()))
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }
}
