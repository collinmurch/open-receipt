import CoreGraphics
import CryptoKit
import Foundation
import ReceiptKit

struct ReceiptModelResponse {
  let content: Data
  let durationSeconds: Double
  let wasCached: Bool
}

enum ReceiptModelClient {
  typealias Respond = @Sendable ([ReceiptPage]) async throws -> Data

  static func privateCloudCompute(configuration: ReceiptParserConfiguration) -> Respond {
    { try await ReceiptParser.responseData(pages: $0, configuration: configuration) }
  }

  static func response(
    pages: [ReceiptPage],
    cacheDirectory: URL,
    cachedOnly: Bool,
    configuration: ReceiptParserConfiguration = .standard,
    respond: Respond
  ) async throws -> ReceiptModelResponse {
    let responseURL = try cacheURL(for: pages, configuration: configuration, in: cacheDirectory)

    if cachedOnly {
      guard FileManager.default.fileExists(atPath: responseURL.path) else {
        throw ClientError.cacheMiss(responseURL.deletingPathExtension().lastPathComponent)
      }
      return ReceiptModelResponse(
        content: try Data(contentsOf: responseURL),
        durationSeconds: 0,
        wasCached: true)
    }

    let clock = ContinuousClock()
    let started = clock.now
    let content = try await respond(pages)
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    try content.write(to: responseURL, options: .atomic)
    return ReceiptModelResponse(
      content: content,
      durationSeconds: (clock.now - started) / .seconds(1),
      wasCached: false)
  }

  static func cacheURL(
    for pages: [ReceiptPage],
    configuration: ReceiptParserConfiguration = .standard,
    in directory: URL
  ) throws -> URL {
    let key = try cacheKey(for: pages, configuration: configuration)
    return directory.appending(path: "\(key).json")
  }

  static func cacheKey(
    for pages: [ReceiptPage],
    configuration: ReceiptParserConfiguration = .standard
  ) throws -> String {
    var hasher = SHA256()
    hasher.update(data: Data("v\(ReceiptModelContract.version)\n".utf8))
    if let variant = configuration.variantDescription {
      hasher.update(data: Data("\(variant)\n".utf8))
    }
    hasher.update(data: Data(ReceiptModelContract.instructions.utf8))
    hasher.update(data: Data(ReceiptModelContract.prompt.utf8))
    for (index, page) in pages.enumerated() {
      let image = page.image
      guard let pixels = image.dataProvider?.data as Data? else {
        throw ClientError.imageDataUnavailable
      }
      let header = [
        image.width, image.height, image.bitsPerPixel, image.bytesPerRow,
        Int(image.bitmapInfo.rawValue), Int(page.orientation.rawValue),
      ]
      hasher.update(data: Data("\(ReceiptModelContract.imageLabel(at: index)) \(header)\n".utf8))
      hasher.update(data: pixels)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  enum ClientError: LocalizedError {
    case cacheMiss(String)
    case imageDataUnavailable

    var errorDescription: String? {
      switch self {
      case .cacheMiss(let key): "No cached response exists for request \(key)."
      case .imageDataUnavailable: "Could not read receipt page pixels."
      }
    }
  }
}
