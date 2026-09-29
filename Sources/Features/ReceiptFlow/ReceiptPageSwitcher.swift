import SwiftUI

/// A page of a completed receipt.
enum ReceiptReviewPage: Hashable {
  case receipt
  case payments
}

/// Switches a completed receipt between its items and its payment requests.
struct ReceiptPageSwitcher: View {
  @Binding var selection: ReceiptReviewPage
  @Namespace private var selectionIndicator

  var body: some View {
    HStack(spacing: 0) {
      item(.receipt, title: "Receipt", systemImage: "doc.text")
      item(.payments, title: "Payments", systemImage: "dollarsign")
    }
    .padding(4)
    .glassEffect(.regular.interactive(), in: .capsule)
    .animation(.smooth(duration: 0.3), value: selection)
    .sensoryFeedback(.selection, trigger: selection)
  }

  private func item(
    _ page: ReceiptReviewPage,
    title: String,
    systemImage: String
  ) -> some View {
    let isSelected = selection == page
    return Button {
      selection = page
    } label: {
      VStack(spacing: 2) {
        Image(systemName: systemImage)
          .font(.title3)
          .frame(height: 24)
        Text(title)
          .font(.caption2.weight(.medium))
      }
      .frame(minWidth: 92, minHeight: 52)
      .foregroundStyle(
        isSelected
          ? AnyShapeStyle(TintShapeStyle.tint) : AnyShapeStyle(HierarchicalShapeStyle.primary)
      )
      .background {
        if isSelected {
          Capsule()
            .fill(.primary.opacity(0.1))
            .matchedGeometryEffect(id: "selection", in: selectionIndicator)
        }
      }
      .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
