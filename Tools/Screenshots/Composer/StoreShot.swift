import CoreGraphics

/// The marketing copy and art direction for one App Store screenshot. `name` matches a capture
/// written by `ScreenshotCapture`.
struct StoreShot {
  let name: String
  let headline: String
  /// The `screenshotHighlight` name of the view drawn above the screen.
  let highlight: String
  /// Points added around the highlighted view, such as a list row's cell padding.
  var highlightOutset = CGSize.zero
  /// The lifted view's corner radius in points, or `nil` for a capsule.
  var highlightCornerRadius: CGFloat? = 22
  /// A photo under the frame, relative to `Assets`.
  var backdrop = "Receipts/example-receipt.jpg"

  /// The capture whose receipt wash colors every backdrop.
  static let paletteSource = "03-split"

  static let all = [
    StoreShot(
      name: "01-library",
      headline: "Every receipt,\nkept in one place.",
      highlight: "library-row-Cru Food and Wine Bar",
      highlightOutset: CGSize(width: 16, height: 10),
      highlightCornerRadius: 26),
    StoreShot(
      name: "02-reading",
      headline: "Snap a receipt.\nWatch each line appear.",
      highlight: "receipt-reading-status"),
    StoreShot(
      name: "03-split",
      headline: "Everyone pays\nfor what they ordered.",
      highlight: "receipt-participants"),
    StoreShot(
      name: "04-breakdown",
      headline: "Tax and tip, split fairly.\nDown to the cent.",
      highlight: "request-button",
      highlightCornerRadius: nil),
    StoreShot(
      name: "05-requests",
      headline: "Request from each person\nexactly what they owe.",
      highlight: "request-Jillian",
      highlightOutset: CGSize(width: 16, height: 10),
      highlightCornerRadius: 26),
  ]
}
