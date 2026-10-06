import SwiftUI

/// A toolbar button that opens the breakdown's image full screen, where it can be shared as an
/// image or PDF. It stays disabled until the split is final.
struct ReceiptBreakdownViewButton: ToolbarContent {
  private static let sourceID = "breakdown-view-button"

  let breakdown: ReceiptBreakdown?
  @Binding var viewed: ViewedBreakdown?
  let transition: Namespace.ID

  var body: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button("View Breakdown", systemImage: "photo") {
        if let breakdown { open(breakdown) }
      }
      .disabled(breakdown == nil)
      .accessibilityHint(breakdown == nil ? "Assign every item to view the breakdown" : "")
    }
    .matchedTransitionSource(id: Self.sourceID, in: transition)
  }

  /// Draws the card before presenting, so the viewer zooms in with it rather than drawing
  /// mid-transition.
  private func open(_ breakdown: ReceiptBreakdown) {
    let image = ReceiptBreakdownRenderer.image(for: breakdown)
    ReceiptBreakdownRenderer.preparePNG(for: breakdown, from: image)
    viewed = ViewedBreakdown(sourceID: Self.sourceID, breakdown: breakdown, image: image)
  }
}
