#if !SWIFT_PACKAGE
  import CoreGraphics
  import Foundation
  import ImageIO
  import XCTest

  @testable import open_receipt

  final class ReceiptPhotoImporterTests: XCTestCase {
    func testAppliesImageMetadataOrientation() async throws {
      let data = try makeImageData(orientation: .right)

      let page = try XCTUnwrap(ReceiptPhotoImporter.page(from: data, pageIndex: 3))

      XCTAssertEqual(page.image.width, 1)
      XCTAssertEqual(page.image.height, 2)
      XCTAssertEqual(page.orientation, .up)
      XCTAssertEqual(page.pageIndex, 3)
    }

    func testScalesLargePhotosDownToMaximumDimension() throws {
      let data = try makeImageData(orientation: .up, width: 100, height: 50)

      let page = try XCTUnwrap(
        ReceiptPhotoImporter.page(from: data, pageIndex: 0, maximumPixelDimension: 20))

      XCTAssertEqual(page.image.width, 20)
      XCTAssertEqual(page.image.height, 10)
    }

    func testKeepsPhotosWithinMaximumDimensionAtFullSize() throws {
      let data = try makeImageData(orientation: .up, width: 100, height: 50)

      let page = try XCTUnwrap(
        ReceiptPhotoImporter.page(from: data, pageIndex: 0, maximumPixelDimension: 400))

      XCTAssertEqual(page.image.width, 100)
      XCTAssertEqual(page.image.height, 50)
    }

    func testRejectsUnreadableData() {
      XCTAssertNil(ReceiptPhotoImporter.page(from: Data("not an image".utf8), pageIndex: 0))
    }

    private func makeImageData(
      orientation: CGImagePropertyOrientation,
      width: Int = 2,
      height: Int = 1
    ) throws -> Data {
      var pixels = Data()
      for index in 0..<(width * height) {
        pixels.append(contentsOf: index.isMultiple(of: 2) ? [255, 0, 0, 255] : [0, 0, 255, 255])
      }
      let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
      let image = try XCTUnwrap(
        CGImage(
          width: width,
          height: height,
          bitsPerComponent: 8,
          bitsPerPixel: 32,
          bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
          provider: provider,
          decode: nil,
          shouldInterpolate: false,
          intent: .defaultIntent))
      let data = NSMutableData()
      let destination = try XCTUnwrap(
        CGImageDestinationCreateWithData(data, "public.tiff" as CFString, 1, nil))
      CGImageDestinationAddImage(
        destination,
        image,
        [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary)
      XCTAssertTrue(CGImageDestinationFinalize(destination))
      return data as Data
    }
  }
#endif
