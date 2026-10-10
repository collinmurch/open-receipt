import ImageIO
import SwiftUI

/// The rounded tile a receipt page, or the place to add one, sits in.
struct ReceiptPageTileShape: InsettableShape {
  var inset: CGFloat = 0

  func path(in rect: CGRect) -> Path {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
      .inset(by: inset)
      .path(in: rect)
  }

  func inset(by amount: CGFloat) -> ReceiptPageTileShape {
    ReceiptPageTileShape(inset: inset + amount)
  }
}

/// A receipt page drawn small from its stored image.
struct ReceiptPageThumbnail: View {
  static let aspectRatio: CGFloat = 0.72

  let url: URL?
  @State private var image: CGImage?

  var body: some View {
    ReceiptPageTileShape()
      .fill(.background.secondary)
      .aspectRatio(Self.aspectRatio, contentMode: .fit)
      .overlay {
        if let image {
          Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
        } else {
          ProgressView()
        }
      }
      .clipShape(ReceiptPageTileShape())
      .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
      .animation(.smooth(duration: 0.25), value: image != nil)
      .task(id: url) {
        guard let url else { return }
        image = await Self.thumbnail(for: url)
      }
  }

  /// Page files never change once written, so a thumbnail stays good for as long as it's kept.
  private static let thumbnails: NSCache<NSURL, CGImage> = {
    let cache = NSCache<NSURL, CGImage>()
    cache.countLimit = 40
    return cache
  }()

  private static func thumbnail(for url: URL) async -> CGImage? {
    if let cached = thumbnails.object(forKey: url as NSURL) { return cached }
    let thumbnail = await Task.detached(priority: .userInitiated) { () -> CGImage? in
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
      let options =
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 600,
        ] as CFDictionary
      return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }.value
    if let thumbnail { thumbnails.setObject(thumbnail, forKey: url as NSURL) }
    return thumbnail
  }
}
