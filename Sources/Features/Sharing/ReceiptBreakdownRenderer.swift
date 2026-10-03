import SwiftUI

/// Draws breakdown cards as images and PDFs. Cards are always light, so they read the same in
/// whatever conversation they land in.
@MainActor
enum ReceiptBreakdownRenderer {
  static let width: CGFloat = 390
  static let scale: CGFloat = 3

  /// Recent PNG encodings, newest last. A breakdown is a snapshot of everything its card shows,
  /// so an equal breakdown always encodes to the same image.
  private static var pngs: [(breakdown: ReceiptBreakdown, data: Task<Data?, Never>)] = []
  private static let pngLimit = 16

  /// The breakdown's PNG, drawn and encoded once and reused for later shares and messages.
  static func pngData(for breakdown: ReceiptBreakdown) async -> Data? {
    await pngTask(for: breakdown, image: nil).value
  }

  /// Starts encoding the breakdown's PNG ahead of a share, from `image` when it is already drawn.
  static func preparePNG(for breakdown: ReceiptBreakdown, from image: UIImage? = nil) {
    _ = pngTask(for: breakdown, image: image)
  }

  static func image(for breakdown: ReceiptBreakdown) -> UIImage? {
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

  /// Drawing has to happen on the main actor, but encoding doesn't, so it runs detached.
  private static func pngTask(
    for breakdown: ReceiptBreakdown,
    image: UIImage?
  ) -> Task<Data?, Never> {
    if let cached = pngs.first(where: { $0.breakdown == breakdown }) {
      return cached.data
    }
    let image = image ?? self.image(for: breakdown)
    let task = Task.detached(priority: .userInitiated) { image?.pngData() }
    pngs.append((breakdown, task))
    if pngs.count > pngLimit { pngs.removeFirst() }
    return task
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
