import SwiftUI

/// Draws breakdown cards as images and PDFs. Cards are always light, so they read the same in
/// whatever conversation they land in.
@MainActor
enum ReceiptBreakdownRenderer {
  static let width: CGFloat = 390
  static let scale: CGFloat = 3

  /// Recently drawn cards, costed by their bitmap size. The cache lets go of them under memory
  /// pressure, and a card it dropped is drawn again when it's next needed.
  private static let drawings: NSCache<DrawingKey, Drawing> = {
    let cache = NSCache<DrawingKey, Drawing>()
    cache.totalCostLimit = 32 * 1024 * 1024
    return cache
  }()

  /// The breakdown's card, drawn once and reused.
  @discardableResult
  static func image(for breakdown: ReceiptBreakdown) -> UIImage? {
    drawing(for: breakdown).image
  }

  /// The breakdown's card encoded as a PNG.
  static func pngData(for breakdown: ReceiptBreakdown) async -> Data? {
    await png(for: breakdown).value
  }

  /// Starts encoding the breakdown's card as a PNG, so several started together encode side by
  /// side. The task holds the card until it's done.
  static func png(for breakdown: ReceiptBreakdown) -> Task<Data?, Never> {
    drawing(for: breakdown).png
  }

  static func pdfData(for breakdown: ReceiptBreakdown) -> Data? {
    let data = NSMutableData()
    renderer(for: breakdown).render { size, render in
      var mediaBox = CGRect(origin: .zero, size: size)
      guard let consumer = CGDataConsumer(data: data),
        let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
      else { return }
      context.beginPDFPage(nil)
      render(context)
      context.endPDFPage()
      context.closePDF()
    }
    return data.length > 0 ? data as Data : nil
  }

  private static func drawing(for breakdown: ReceiptBreakdown) -> Drawing {
    let key = DrawingKey(breakdown)
    if let cached = drawings.object(forKey: key) {
      return cached
    }
    let renderer = renderer(for: breakdown)
    renderer.scale = scale
    let drawing = Drawing(image: renderer.uiImage)
    drawings.setObject(drawing, forKey: key, cost: drawing.cost)
    return drawing
  }

  private static func renderer(for breakdown: ReceiptBreakdown) -> ImageRenderer<some View> {
    let renderer = ImageRenderer(
      content: ReceiptBreakdownCard(breakdown: breakdown)
        .frame(width: width)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large))
    renderer.proposedSize = ProposedViewSize(width: width, height: nil)
    renderer.isOpaque = true
    return renderer
  }
}

/// A breakdown as a cache key. A breakdown is a snapshot of everything its card shows but the
/// locale its amounts are written in, so an equal breakdown in the same locale always draws the
/// same image.
private final class DrawingKey: NSObject {
  let breakdown: ReceiptBreakdown
  let locale = Locale.current

  init(_ breakdown: ReceiptBreakdown) {
    self.breakdown = breakdown
  }

  override var hash: Int {
    breakdown.title.hashValue
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? DrawingKey else { return false }
    return other.breakdown == breakdown && other.locale == locale
  }
}

@MainActor
private final class Drawing {
  let image: UIImage?

  init(image: UIImage?) {
    self.image = image
  }

  /// The card's PNG, encoded the first time it's asked for. Drawing has to happen on the main
  /// actor, but encoding doesn't, so it runs detached.
  lazy var png: Task<Data?, Never> = Task.detached(priority: .userInitiated) { [image] in
    image?.pngData()
  }

  var cost: Int {
    guard let image = image?.cgImage else { return 0 }
    return image.bytesPerRow * image.height
  }
}
