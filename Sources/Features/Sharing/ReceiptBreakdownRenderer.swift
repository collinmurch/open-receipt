import SwiftUI

/// Draws breakdown cards as images and PDFs. Cards are always light, so they read the same in
/// whatever conversation they land in.
@MainActor
enum ReceiptBreakdownRenderer {
  static let width: CGFloat = 390
  static let scale: CGFloat = 3

  /// Recently drawn cards, newest last. A breakdown is a snapshot of everything its card shows,
  /// so an equal breakdown always draws the same image.
  private static var drawings: [Drawing] = []
  private static let drawingLimit = 16

  private struct Drawing {
    let breakdown: ReceiptBreakdown
    let image: UIImage?
    let png: Task<Data?, Never>
  }

  /// The breakdown's card, drawn once and reused. Drawing it also starts encoding its PNG, so a
  /// share or message that follows finds it ready.
  @discardableResult
  static func image(for breakdown: ReceiptBreakdown) -> UIImage? {
    drawing(for: breakdown).image
  }

  /// The breakdown's card encoded as a PNG.
  static func pngData(for breakdown: ReceiptBreakdown) async -> Data? {
    await drawing(for: breakdown).png.value
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

  /// Drawing has to happen on the main actor, but encoding doesn't, so it runs detached.
  private static func drawing(for breakdown: ReceiptBreakdown) -> Drawing {
    if let cached = drawings.first(where: { $0.breakdown == breakdown }) {
      return cached
    }
    let renderer = renderer(for: breakdown)
    renderer.scale = scale
    let image = renderer.uiImage
    let drawing = Drawing(
      breakdown: breakdown,
      image: image,
      png: Task.detached(priority: .userInitiated) { image?.pngData() })
    drawings.append(drawing)
    if drawings.count > drawingLimit { drawings.removeFirst() }
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
