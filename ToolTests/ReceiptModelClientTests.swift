import CoreGraphics
import Foundation
import ImageIO
import ReceiptKit
import XCTest

@testable import ReceiptLab

final class ReceiptModelClientTests: XCTestCase {
  func testIdenticalPagesHaveIdenticalCacheKeys() throws {
    let page = try makePage(gray: 255)

    XCTAssertEqual(
      try ReceiptModelClient.cacheKey(for: [page]),
      try ReceiptModelClient.cacheKey(for: [page]))
  }

  func testStandardConfigurationKeepsExistingCacheKey() throws {
    let page = try makePage(gray: 255)

    XCTAssertEqual(
      try ReceiptModelClient.cacheKey(for: [page]),
      try ReceiptModelClient.cacheKey(for: [page], configuration: .standard))
  }

  func testConfigurationVariantInvalidatesCacheKey() throws {
    let page = try makePage(gray: 255)

    XCTAssertNotEqual(
      try ReceiptModelClient.cacheKey(for: [page]),
      try ReceiptModelClient.cacheKey(
        for: [page], configuration: .init(reasoningLevel: .light)))
  }

  func testPixelLimitsHaveDistinctCacheKeys() throws {
    let page = try makePage(gray: 255)

    XCTAssertNotEqual(
      try ReceiptModelClient.cacheKey(for: [page], configuration: .init(maxPixelDimension: 1024)),
      try ReceiptModelClient.cacheKey(for: [page], configuration: .init(maxPixelDimension: 2048)))
  }

  func testImageChangeInvalidatesCacheKey() throws {
    XCTAssertNotEqual(
      try ReceiptModelClient.cacheKey(for: [makePage(gray: 255)]),
      try ReceiptModelClient.cacheKey(for: [makePage(gray: 0)]))
  }

  func testOrientationChangeInvalidatesCacheKey() throws {
    let image = try makeImage(gray: 255)

    XCTAssertNotEqual(
      try ReceiptModelClient.cacheKey(for: [makePage(image: image, orientation: .up)]),
      try ReceiptModelClient.cacheKey(for: [makePage(image: image, orientation: .right)]))
  }

  func testPageOrderChangesCacheKey() throws {
    let white = try makePage(gray: 255)
    let black = try makePage(gray: 0)

    XCTAssertNotEqual(
      try ReceiptModelClient.cacheKey(for: [white, black]),
      try ReceiptModelClient.cacheKey(for: [black, white]))
  }

  func testCachedResponseDoesNotCallModel() async throws {
    let directory = makeCacheDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let page = try makePage(gray: 255)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: ReceiptModelClient.cacheURL(for: [page], in: directory))

    let response = try await ReceiptModelClient.response(
      pages: [page],
      cacheDirectory: directory,
      cachedOnly: true,
      respond: { _ in
        XCTFail("Model should not be called")
        return Data()
      })

    XCTAssertTrue(response.wasCached)
    XCTAssertEqual(response.content, Data("{}".utf8))
  }

  func testCacheMissDoesNotCallModel() async throws {
    let directory = makeCacheDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
      _ = try await ReceiptModelClient.response(
        pages: [makePage(gray: 255)],
        cacheDirectory: directory,
        cachedOnly: true,
        respond: { _ in
          XCTFail("Model should not be called")
          return Data()
        })
      XCTFail("Expected a cache miss")
    } catch let error as ReceiptModelClient.ClientError {
      guard case .cacheMiss = error else { return XCTFail("Unexpected error: \(error)") }
    }
  }

  func testLiveResponseIsNotMarkedCached() async throws {
    let directory = makeCacheDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let response = try await ReceiptModelClient.response(
      pages: [makePage(gray: 255)],
      cacheDirectory: directory,
      cachedOnly: false,
      respond: { _ in Data("{\"live\":true}".utf8) })

    XCTAssertFalse(response.wasCached)
    XCTAssertEqual(response.content, Data("{\"live\":true}".utf8))
  }

  func testLiveResponseIsWrittenToCache() async throws {
    let directory = makeCacheDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let page = try makePage(gray: 255)

    _ = try await ReceiptModelClient.response(
      pages: [page],
      cacheDirectory: directory,
      cachedOnly: false,
      respond: { _ in Data("{\"live\":true}".utf8) })

    XCTAssertEqual(
      try Data(contentsOf: ReceiptModelClient.cacheURL(for: [page], in: directory)),
      Data("{\"live\":true}".utf8))
  }

  func testModelReceivesPagesInGivenOrder() async throws {
    let directory = makeCacheDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let pages = [
      makePage(image: try makeImage(gray: 255), pageIndex: 0),
      makePage(image: try makeImage(gray: 0), pageIndex: 1),
    ]

    _ = try await ReceiptModelClient.response(
      pages: pages,
      cacheDirectory: directory,
      cachedOnly: false,
      respond: { received in
        XCTAssertEqual(received.map(\.pageIndex), [0, 1])
        return Data("{}".utf8)
      })
  }

  private func makeCacheDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  private func makePage(gray: UInt8) throws -> ReceiptPage {
    makePage(image: try makeImage(gray: gray))
  }

  private func makeImage(gray: UInt8) throws -> CGImage {
    let data = Data([gray, gray, gray, 255, gray, gray, gray, 255])
    let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
    return try XCTUnwrap(
      CGImage(
        width: 2,
        height: 1,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: 8,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent))
  }

  private func makePage(
    image: CGImage,
    orientation: CGImagePropertyOrientation = .up,
    pageIndex: Int = 0
  ) -> ReceiptPage {
    ReceiptPage(
      image: image,
      orientation: orientation,
      sourceURL: URL(fileURLWithPath: "fixture.png"),
      pageIndex: pageIndex)
  }
}
