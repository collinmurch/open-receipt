import SwiftUI

/// Breakdown cards opened full screen to read up close before sharing them, swiping between them
/// when there are several.
struct ReceiptBreakdownViewer: View {
  let breakdowns: [ReceiptBreakdown]
  /// The cards already drawn by whatever opened the viewer, nil where one isn't drawn yet.
  let images: [UIImage?]
  @Binding var selection: Int

  @State private var drawnImages: [Int: UIImage] = [:]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let current = breakdowns[min(max(selection, 0), breakdowns.count - 1)]
    NavigationStack {
      TabView(selection: $selection) {
        ForEach(breakdowns.indices, id: \.self) { index in
          page(index)
            .tag(index)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: breakdowns.count > 1 ? .always : .never))
      .indexViewStyle(.page(backgroundDisplayMode: .interactive))
      .ignoresSafeArea()
      .receiptBackground(current.style)
      .navigationTitle(current.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(role: .close) { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: current, preview: SharePreview(current.title, image: current)) {
            Label("Share", systemImage: "square.and.arrow.up")
          }
        }
      }
    }
  }

  private func page(_ index: Int) -> some View {
    ZStack {
      if let image = images[index] ?? drawnImages[index] {
        ZoomableImage(image: image, cornerRadius: 18)
          .ignoresSafeArea()
          .accessibilityElement()
          .accessibilityLabel(breakdowns[index].title)
          .accessibilityAddTraits(.isImage)
      } else {
        ProgressView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task { draw(index) }
  }

  private func draw(_ index: Int) {
    guard images[index] == nil, drawnImages[index] == nil else { return }
    let image = ReceiptBreakdownRenderer.image(for: breakdowns[index])
    withAnimation(.smooth(duration: 0.25)) { drawnImages[index] = image }
  }
}

/// A breakdown to open in the viewer, zooming from the view that registered `sourceID` as its
/// transition source.
struct ViewedBreakdown: Identifiable {
  let sourceID: AnyHashable
  let breakdown: ReceiptBreakdown
  let image: UIImage?

  var id: AnyHashable { sourceID }
}

extension View {
  /// Opens `viewed` full screen, zooming out of its transition source in `namespace`.
  func breakdownViewer(_ viewed: Binding<ViewedBreakdown?>, in namespace: Namespace.ID)
    -> some View
  {
    fullScreenCover(item: viewed) { viewed in
      ReceiptBreakdownViewer(
        breakdowns: [viewed.breakdown], images: [viewed.image], selection: .constant(0)
      )
      .navigationTransition(.zoom(sourceID: viewed.sourceID, in: namespace))
    }
  }

  /// Opens `breakdowns` full screen at `selection`, which follows the swipes between them. It
  /// zooms out of and back into whichever view registered the selected index in `namespace`.
  func breakdownViewer(
    isPresented: Binding<Bool>,
    breakdowns: [ReceiptBreakdown],
    images: [UIImage?],
    selection: Binding<Int>,
    in namespace: Namespace.ID
  ) -> some View {
    fullScreenCover(isPresented: isPresented) {
      ReceiptBreakdownViewer(breakdowns: breakdowns, images: images, selection: selection)
        .navigationTransition(.zoom(sourceID: selection.wrappedValue, in: namespace))
    }
  }
}
