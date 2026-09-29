import SwiftUI

/// A toolbar button that shares a breakdown as an image or PDF. It stays disabled until the
/// split is final.
struct ReceiptBreakdownShareButton: View {
  let breakdown: ReceiptBreakdown?

  var body: some View {
    if let breakdown {
      ShareLink(item: breakdown, preview: SharePreview(breakdown.title, image: breakdown)) {
        Label("Share Breakdown", systemImage: "square.and.arrow.up")
      }
    } else {
      Button("Share Breakdown", systemImage: "square.and.arrow.up") {}
        .disabled(true)
        .accessibilityHint("Assign every item to share the breakdown")
    }
  }
}
