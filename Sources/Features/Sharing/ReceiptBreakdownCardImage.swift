import SwiftUI

/// A drawn breakdown card with rounded corners and a soft shadow, which the viewer zooms out of
/// and back into under `sourceID`.
struct ReceiptBreakdownCardImage: View {
  let image: UIImage
  let cornerRadius: CGFloat
  let sourceID: AnyHashable
  let transition: Namespace.ID

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    Image(uiImage: image)
      .resizable()
      .scaledToFit()
      .clipShape(shape)
      // A shape's shadow is drawn from its outline, which stays cheap while the card moves.
      .background {
        shape
          .fill(.black)
          .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
      }
      .matchedTransitionSource(id: sourceID, in: transition) { $0.clipShape(shape) }
  }
}
