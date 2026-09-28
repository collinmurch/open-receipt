import Foundation
import ImageIO
import PhotosUI
import SwiftUI

enum ReceiptPhotoImporter {
  /// The longest side of an imported page. Photos are decoded straight to this size, which keeps
  /// a 48-megapixel photo from being expanded to full resolution in memory.
  static let maximumPixelDimension = 4096

  /// Reads the selected photos concurrently and returns them in selection order, skipping any
  /// that cannot be decoded.
  static func pages(from items: [PhotosPickerItem]) async -> [ReceiptPage] {
    let loaded = await withTaskGroup(of: (Int, ReceiptPage?).self) { group in
      for (index, item) in items.enumerated() {
        group.addTask {
          guard let data = try? await item.loadTransferable(type: Data.self) else {
            return (index, nil)
          }
          return (index, ReceiptPhotoImporter.page(from: data, pageIndex: index))
        }
      }
      var pages: [(Int, ReceiptPage)] = []
      for await (index, page) in group {
        if let page { pages.append((index, page)) }
      }
      return pages
    }
    return loaded.sorted { $0.0 < $1.0 }.enumerated().map { pageIndex, element in
      ReceiptPage(
        image: element.1.image,
        orientation: element.1.orientation,
        sourceURL: element.1.sourceURL,
        pageIndex: pageIndex)
    }
  }

  /// Decodes an upright page no larger than `maximumPixelDimension` on its longest side.
  static func page(
    from data: Data,
    pageIndex: Int,
    maximumPixelDimension: Int = ReceiptPhotoImporter.maximumPixelDimension
  ) -> ReceiptPage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
      return nil
    }
    let thumbnailOptions =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
      ] as CFDictionary
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      return nil
    }
    return ReceiptPage(
      image: image,
      orientation: .up,
      sourceURL: URL(fileURLWithPath: "photo-library"),
      pageIndex: pageIndex)
  }
}
