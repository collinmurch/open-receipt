import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders App Store screenshots, and the header and search result artwork, from the screens and
/// slips `ScreenshotCapture` wrote.
///
///     ScreenshotComposer --captures <dir> --assets <dir> --output <dir> [--only <name>]
@main
struct ScreenshotComposer {
  static func main() {
    do {
      let options = try Options(CommandLine.arguments.dropFirst())
      var shots = StoreShot.all
      var reviewShots = StoreShot.reviewOnly
      var artwork = Artwork.allCases
      if let name = options.only {
        shots = StoreShot.all.first { $0.name.contains(name) }.map { [$0] } ?? []
        reviewShots = StoreShot.reviewOnly.first { $0.contains(name) }.map { [$0] } ?? []
        artwork = Artwork.allCases.filter { $0.rawValue == name }
        guard !shots.isEmpty || !reviewShots.isEmpty || !artwork.isEmpty else {
          throw ComposerError.unknownShot(name)
        }
      }

      let photo = try loadImage(options.photo)
      for appearance in StoreAppearance.allCases {
        let captures = options.captures.appending(path: appearance.rawValue)
        let output = options.output.appending(path: appearance.rawValue)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let palette = try? Capture(directory: captures, name: StoreShot.paletteSource)
        for shot in shots {
          let capture = try Capture(directory: captures, name: shot.name)
          let frame = StoreFrame(
            shot: shot,
            capture: capture,
            backdrop: photo,
            swatches: try (palette ?? capture).edgeSwatches(rows: 3),
            appearance: appearance)
          try write(
            render(frame, size: StoreFrame.size, name: shot.name),
            to: output.appending(path: "\(shot.name).png"))
        }
      }

      let artworkOutput = options.output.appending(path: "artwork")
      try FileManager.default.createDirectory(at: artworkOutput, withIntermediateDirectories: true)
      for piece in artwork {
        try write(piece.render(options), to: artworkOutput.appending(path: "\(piece.rawValue).png"))
      }

      let review = options.output.appending(path: "review")
      try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
      for name in reviewShots {
        let capture = options.captures.appending(path: StoreAppearance.light.rawValue)
        try write(
          loadImage(capture.appending(path: "\(name).png")),
          to: review.appending(path: "\(name).png"))
      }
    } catch {
      FileHandle.standardError.write(Data("ScreenshotComposer: \(error)\n".utf8))
      exit(1)
    }
  }

  static func render(_ view: some View, size: CGSize, name: String) throws -> CGImage {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    renderer.isOpaque = true
    renderer.proposedSize = ProposedViewSize(size)
    guard let image = renderer.cgImage else { throw ComposerError.render(name) }
    return image
  }

  /// Writes `image` as a PNG without an alpha channel, which App Store Connect rejects.
  private static func write(_ image: CGImage, to url: URL) throws {
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw ComposerError.render(url.lastPathComponent) }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let opaque = context.makeImage() else {
      throw ComposerError.render(url.lastPathComponent)
    }
    CGImageDestinationAddImage(destination, opaque, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw ComposerError.render(url.lastPathComponent)
    }
    print("Wrote \(url.path(percentEncoded: false))")
  }
}

/// Artwork for the App Store product page and search results, beside the screenshots.
private enum Artwork: String, CaseIterable {
  case header
  case search

  func render(_ options: Options) throws -> CGImage {
    switch self {
    case .header:
      let directory = options.captures.appending(path: "breakdowns", directoryHint: .isDirectory)
      let names = try JSONDecoder().decode(
        [String].self, from: Data(contentsOf: directory.appending(path: "breakdowns.json")))
      let people = try names.filter { $0 != "overview.png" }.map {
        try loadImage(directory.appending(path: $0))
      }
      return try ScreenshotComposer.render(
        HeaderArtwork(slips: people), size: HeaderArtwork.size, name: rawValue)
    case .search:
      let captures = options.captures.appending(path: StoreAppearance.light.rawValue)
      let artwork = SearchArtwork(
        capture: try Capture(directory: captures, name: "search"),
        photo: try loadImage(options.photo))
      return try ScreenshotComposer.render(artwork, size: SearchArtwork.size, name: rawValue)
    }
  }
}

private struct Options {
  var captures: URL
  var assets: URL
  var output: URL
  var only: String?

  init(_ arguments: ArraySlice<String>) throws {
    var values: [String: String] = [:]
    var iterator = arguments.makeIterator()
    while let flag = iterator.next() {
      guard flag.hasPrefix("--"), let value = iterator.next() else {
        throw OptionsError.usage
      }
      values[String(flag.dropFirst(2))] = value
    }
    guard let captures = values["captures"], let assets = values["assets"],
      let output = values["output"]
    else { throw OptionsError.usage }
    self.captures = URL(filePath: captures, directoryHint: .isDirectory)
    self.assets = URL(filePath: assets, directoryHint: .isDirectory)
    self.output = URL(filePath: output, directoryHint: .isDirectory)
    only = values["only"].flatMap { $0.isEmpty ? nil : $0 }
  }

  /// The receipt photo under the screenshots and the search artwork.
  var photo: URL {
    assets.appending(path: "Receipts/example-receipt.jpg")
  }

  enum OptionsError: Error, CustomStringConvertible {
    case usage

    var description: String {
      "usage: ScreenshotComposer --captures <dir> --assets <dir> --output <dir> [--only <name>]"
    }
  }
}
