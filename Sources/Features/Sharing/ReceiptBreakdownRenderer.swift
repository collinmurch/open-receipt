import SwiftUI

/// Draws breakdown cards as images and PDFs. Cards are always light, so they read the same in
/// whatever conversation they land in.
@MainActor
enum ReceiptBreakdownRenderer {
  static let width: CGFloat = 390
  static let scale: CGFloat = 3

  static func pngData(for breakdown: ReceiptBreakdown) -> Data? {
    image(for: breakdown)?.pngData()
  }

  static func image(
    for breakdown: ReceiptBreakdown,
    scale: CGFloat = ReceiptBreakdownRenderer.scale
  ) -> UIImage? {
    let renderer = renderer(for: breakdown)
    renderer.scale = scale
    return renderer.uiImage
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

  private static func renderer(for breakdown: ReceiptBreakdown) -> ImageRenderer<some View> {
    let renderer = ImageRenderer(
      content: ReceiptBreakdownCard(breakdown: breakdown)
        .frame(width: width)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large))
    renderer.proposedSize = ProposedViewSize(width: width, height: nil)
    return renderer
  }
}
