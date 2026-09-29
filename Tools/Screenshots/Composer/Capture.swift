import CoreGraphics
import Foundation
import ImageIO

/// A screen written by `ScreenshotCapture`, with the manifest that locates its content.
struct Capture {
  struct Manifest: Decodable {
    let scale: CGFloat
    let contentTop: CGFloat
  }

  let image: CGImage
  let manifest: Manifest
  /// Frames the app recorded for views marked with `screenshotHighlight`, in points.
  let highlights: [String: CGRect]

  init(directory: URL, name: String) throws {
    image = try loadImage(directory.appending(path: "\(name).png"))
    manifest = try JSONDecoder().decode(
      Manifest.self, from: Data(contentsOf: directory.appending(path: "\(name).json")))
    highlights = try JSONDecoder().decode(
      [String: CGRect].self,
      from: Data(contentsOf: directory.appending(path: "\(name).highlights.json")))
  }

  /// The screen below the status bar's text, in pixels. It starts `headroom` points above the
  /// navigation bar so its buttons don't touch the card's edge.
  var contentRect: CGRect {
    let headroom: CGFloat = 18
    let top = (max(manifest.contentTop - headroom, 0) * manifest.scale).rounded()
    return CGRect(
      x: 0, y: top, width: CGFloat(image.width), height: CGFloat(image.height) - top)
  }

  /// Where `identifier` sits on the screen, in pixels.
  func highlightRect(_ identifier: String, outset: CGSize = .zero) throws -> CGRect {
    guard let frame = highlights[identifier] else {
      throw ComposerError.missingHighlight(identifier)
    }
    let rect = frame.insetBy(dx: -outset.width, dy: -outset.height)
    let scale = manifest.scale
    return CGRect(
      x: rect.minX * scale, y: rect.minY * scale,
      width: rect.width * scale, height: rect.height * scale
    ).integral
  }

  /// Average colors down the screen's leading and trailing edges, top to bottom. Receipt
  /// screens draw their wash there, outside the grouped content.
  func edgeSwatches(rows: Int) throws -> (leading: [Swatch], trailing: [Swatch]) {
    let content = contentRect
    let width = (content.width * 0.03).rounded()
    let leading = CGRect(x: content.minX, y: content.minY, width: width, height: content.height)
    let trailing = CGRect(
      x: content.maxX - width, y: content.minY, width: width, height: content.height)
    return (try averages(of: leading, rows: rows), try averages(of: trailing, rows: rows))
  }

  private func averages(of rect: CGRect, rows: Int) throws -> [Swatch] {
    let strip = try crop(rect)
    var pixels = [UInt8](repeating: 0, count: rows * 4)
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: &pixels, width: 1, height: rows, bitsPerComponent: 8, bytesPerRow: 4,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw ComposerError.crop(rect) }
    context.interpolationQuality = .high
    context.draw(strip, in: CGRect(x: 0, y: 0, width: 1, height: rows))
    return (0..<rows).map { row in
      let offset = row * 4
      return Swatch(
        red: Double(pixels[offset]) / 255,
        green: Double(pixels[offset + 1]) / 255,
        blue: Double(pixels[offset + 2]) / 255)
    }
  }

  func crop(_ rect: CGRect) throws -> CGImage {
    guard let cropped = image.cropping(to: rect) else { throw ComposerError.crop(rect) }
    return cropped
  }
}

/// An opaque sRGB color.
struct Swatch {
  var red: Double
  var green: Double
  var blue: Double

  /// This color moved `amount` of the way toward `other`.
  func mixed(with other: Swatch, by amount: Double) -> Swatch {
    Swatch(
      red: red + (other.red - red) * amount,
      green: green + (other.green - green) * amount,
      blue: blue + (other.blue - blue) * amount)
  }

  static let white = Swatch(red: 1, green: 1, blue: 1)
  static let black = Swatch(red: 0, green: 0, blue: 0)
}

enum ComposerError: Error, CustomStringConvertible {
  case unreadableImage(URL)
  case missingHighlight(String)
  case crop(CGRect)
  case render(String)
  case unknownShot(String)

  var description: String {
    switch self {
    case .unreadableImage(let url): "Couldn't read \(url.path)."
    case .missingHighlight(let id): "The capture has no frame for \(id)."
    case .crop(let rect): "Couldn't crop \(rect)."
    case .render(let name): "Couldn't render \(name)."
    case .unknownShot(let name): "No StoreShot is named \(name)."
    }
  }
}

func loadImage(_ url: URL) throws -> CGImage {
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { throw ComposerError.unreadableImage(url) }
  return image
}
