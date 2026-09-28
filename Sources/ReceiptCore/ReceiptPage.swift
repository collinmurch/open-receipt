import CoreGraphics
import Foundation
import ImageIO

public struct ReceiptPage: Sendable {
  public let image: CGImage
  public let orientation: CGImagePropertyOrientation
  public let sourceURL: URL
  public let pageIndex: Int

  public init(
    image: CGImage,
    orientation: CGImagePropertyOrientation = .up,
    sourceURL: URL,
    pageIndex: Int
  ) {
    self.image = image
    self.orientation = orientation
    self.sourceURL = sourceURL
    self.pageIndex = pageIndex
  }
}
