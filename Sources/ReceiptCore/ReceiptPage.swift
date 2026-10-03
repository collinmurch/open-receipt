import CoreGraphics
import Foundation
import ImageIO

public struct ReceiptPage: Sendable {
  public let image: CGImage
  public let orientation: CGImagePropertyOrientation

  public init(image: CGImage, orientation: CGImagePropertyOrientation = .up) {
    self.image = image
    self.orientation = orientation
  }

  /// Reads the first image in the file at `url` with the orientation recorded in its metadata,
  /// or returns `nil` when the file can't be decoded. The decoded pixels aren't kept, so a page
  /// held while it is read costs its file size rather than a full bitmap.
  public init?(contentsOf url: URL) {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, options)
    else { return nil }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let rawOrientation = properties?[kCGImagePropertyOrientation] as? UInt32
    self.init(
      image: image,
      orientation: rawOrientation.flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up)
  }
}
