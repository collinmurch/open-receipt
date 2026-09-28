import CoreGraphics
import Foundation
import ImageIO
import XCTest

#if SWIFT_PACKAGE
  @testable import ReceiptKit
#else
  @testable import open_receipt
#endif

final class ReceiptImageNormalizerTests: XCTestCase {
  func testNormalizesUpMirroredOrientation() throws {
    try assertNormalizationMatchesImageIO(.upMirrored)
  }

  func testNormalizesDownOrientation() throws {
    try assertNormalizationMatchesImageIO(.down)
  }

  func testNormalizesDownMirroredOrientation() throws {
    try assertNormalizationMatchesImageIO(.downMirrored)
  }

  func testNormalizesLeftOrientation() throws {
    try assertNormalizationMatchesImageIO(.left)
  }

  func testNormalizesRightOrientationAndSwapsDimensions() throws {
    let image = try makeImage()
    let normalized = try XCTUnwrap(
      ReceiptImageNormalizer.normalized(image, orientation: .right))

    XCTAssertEqual(normalized.width, image.height)
    XCTAssertEqual(normalized.height, image.width)
    try assertNormalizationMatchesImageIO(.right)
  }

  func testNormalizesLeftMirroredOrientationAndSwapsDimensions() throws {
    let image = try makeImage()
    let normalized = try XCTUnwrap(
      ReceiptImageNormalizer.normalized(image, orientation: .leftMirrored))

    XCTAssertEqual(normalized.width, image.height)
    XCTAssertEqual(normalized.height, image.width)
    try assertNormalizationMatchesImageIO(.leftMirrored)
  }

  func testNormalizesRightMirroredOrientation() throws {
    try assertNormalizationMatchesImageIO(.rightMirrored)
  }

  func testUpOrientationReturnsOriginalImage() throws {
    let image = try makeImage()
    let normalized = try XCTUnwrap(
      ReceiptImageNormalizer.normalized(image, orientation: .up))

    XCTAssertTrue(normalized === image)
  }

  private func assertNormalizationMatchesImageIO(
    _ orientation: CGImagePropertyOrientation,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let image = try makeImage()
    let actual = try XCTUnwrap(
      ReceiptImageNormalizer.normalized(image, orientation: orientation),
      file: file,
      line: line)
    let expected = try imageIONormalized(image, orientation: orientation)

    XCTAssertEqual(actual.width, expected.width, file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, file: file, line: line)
    XCTAssertEqual(
      Array(try rgbaData(actual)),
      Array(try rgbaData(expected)),
      file: file,
      line: line)
  }

  private func makeImage() throws -> CGImage {
    let pixels: [UInt8] = [
      255, 0, 0, 255,
      0, 255, 0, 255,
      0, 0, 255, 255,
      0, 255, 255, 255,
      255, 0, 255, 255,
      255, 255, 0, 255,
    ]
    let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
    return try XCTUnwrap(
      CGImage(
        width: 3,
        height: 2,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: 12,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent))
  }

  private func imageIONormalized(
    _ image: CGImage,
    orientation: CGImagePropertyOrientation
  ) throws -> CGImage {
    let data = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(data, "public.tiff" as CFString, 1, nil))
    CGImageDestinationAddImage(
      destination,
      image,
      [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))

    let source = try XCTUnwrap(CGImageSourceCreateWithData(data, nil))
    let options =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(image.width, image.height),
      ] as CFDictionary
    return try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, 0, options))
  }

  private func rgbaData(_ image: CGImage) throws -> Data {
    var data = Data(count: image.width * image.height * 4)
    try data.withUnsafeMutableBytes { bytes in
      let context = try XCTUnwrap(
        CGContext(
          data: bytes.baseAddress,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: image.width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return data
  }
}
