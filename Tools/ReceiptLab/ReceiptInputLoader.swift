import CoreGraphics
import Foundation
import PDFKit
import ReceiptKit

enum ReceiptInputLoader {
  enum LoadError: Error, LocalizedError {
    case fileNotFound(URL)
    case unsupportedFormat(URL)
    case decodingFailed(URL)
    case empty(URL)

    var errorDescription: String? {
      switch self {
      case .fileNotFound(let url): "File not found: \(url.path)"
      case .unsupportedFormat(let url): "Unsupported format: \(url.lastPathComponent)"
      case .decodingFailed(let url): "Failed to decode: \(url.lastPathComponent)"
      case .empty(let url): "No pages decoded from: \(url.lastPathComponent)"
      }
    }
  }

  private static let imageExtensions: Set<String> = [
    "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp", "webp",
  ]

  static func loadFile(_ url: URL) throws -> [ReceiptPage] {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw LoadError.fileNotFound(url)
    }
    if url.pathExtension.lowercased() == "pdf" { return try loadPDF(url) }
    guard imageExtensions.contains(url.pathExtension.lowercased()) else {
      throw LoadError.unsupportedFormat(url)
    }
    return try loadImage(url)
  }

  static func isSupported(_ url: URL) -> Bool {
    imageExtensions.contains(url.pathExtension.lowercased())
      || url.pathExtension.lowercased() == "pdf"
  }

  private static func loadPDF(_ url: URL) throws -> [ReceiptPage] {
    guard let document = PDFDocument(url: url) else { throw LoadError.decodingFailed(url) }
    var pages: [ReceiptPage] = []
    for index in 0..<document.pageCount {
      guard let page = document.page(at: index), let image = render(page) else { continue }
      pages.append(ReceiptPage(image: image))
    }
    guard !pages.isEmpty else { throw LoadError.empty(url) }
    return pages
  }

  private static func render(_ page: PDFPage) -> CGImage? {
    let bounds = page.bounds(for: .mediaBox)
    let scale: CGFloat = 220 / 72
    let width = Int((bounds.width * scale).rounded())
    let height = Int((bounds.height * scale).rounded())
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: context)
    context.restoreGState()
    return context.makeImage()
  }

  private static func loadImage(_ url: URL) throws -> [ReceiptPage] {
    guard let page = ReceiptPage(contentsOf: url) else { throw LoadError.decodingFailed(url) }
    return [page]
  }
}
