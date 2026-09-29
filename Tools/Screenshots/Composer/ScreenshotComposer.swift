import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders App Store screenshots from the screens `ScreenshotCapture` wrote.
///
///     ScreenshotComposer --captures <dir> --assets <dir> --output <dir> [--only <name>]
@main
struct ScreenshotComposer {
  @MainActor
  static func main() {
    do {
      let options = try Options(CommandLine.arguments.dropFirst())
      let shots =
        try options.only.map { name in
          guard let shot = StoreShot.all.first(where: { $0.name.contains(name) }) else {
            throw ComposerError.unknownShot(name)
          }
          return [shot]
        } ?? StoreShot.all

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
            backdrop: try loadImage(options.assets.appending(path: shot.backdrop)),
            swatches: try (palette ?? capture).edgeSwatches(rows: 3),
            appearance: appearance)
          let url = output.appending(path: "\(shot.name).png")
          try writeOpaquePNG(try render(frame, name: shot.name), to: url)
          print("Wrote \(url.path(percentEncoded: false))")
        }
      }
    } catch {
      FileHandle.standardError.write(Data("ScreenshotComposer: \(error)\n".utf8))
      exit(1)
    }
  }

  @MainActor
  private static func render(_ frame: StoreFrame, name: String) throws -> CGImage {
    let renderer = ImageRenderer(content: frame)
    renderer.scale = 1
    renderer.isOpaque = true
    renderer.proposedSize = ProposedViewSize(StoreFrame.size)
    guard let image = renderer.cgImage else { throw ComposerError.render(name) }
    return image
  }

  /// App Store Connect rejects screenshots with an alpha channel.
  private static func writeOpaquePNG(_ image: CGImage, to url: URL) throws {
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

  enum OptionsError: Error, CustomStringConvertible {
    case usage

    var description: String {
      "usage: ScreenshotComposer --captures <dir> --assets <dir> --output <dir> [--only <name>]"
    }
  }
}
