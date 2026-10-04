import ImageIO
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// A receipt's stored scan pages and the actions that change them.
struct ReceiptPagesEditor {
  let pages: [ReceiptDocument.Page]
  let needsRescan: Bool
  let add: @MainActor ([ReceiptPage]) async throws -> Void
  let delete: @MainActor (ReceiptDocument.Page.ID) async throws -> Void
  let reorder: @MainActor ([ReceiptDocument.Page.ID]) async throws -> Void
  let rescan: @MainActor () -> Void
}

struct ReceiptPagesView: View {
  let receiptID: UUID
  let editor: ReceiptPagesEditor
  let style: ReceiptBackgroundStyle
  @State private var pageURLs: [ReceiptDocument.Page.ID: URL] = [:]
  @State private var orderedPageIDs: [ReceiptDocument.Page.ID] = []
  @State private var draggedPageID: ReceiptDocument.Page.ID?
  @State private var previewURL: URL?
  @State private var isScannerPresented = false
  @State private var isPhotoPickerPresented = false
  @State private var photoItems: [PhotosPickerItem] = []
  @State private var isAddingPages = false
  @State private var isRescanConfirmationPresented = false
  @State private var errorDescription: String?
  @State private var haptic = HapticEvent()
  @Environment(\.receiptStorageClient) private var storage
  @Environment(ReceiptRecognitionCenter.self) private var recognitions
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
            ForEach(Array(displayedPages.enumerated()), id: \.element.id) { index, page in
              pageTile(page, number: index + 1)
                .opacity(draggedPageID == page.id ? 0.5 : 1)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            addTile
          }
          .animation(.settle, value: displayedPages.map(\.id))

          if let footnote {
            Text(footnote)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.text], isTargeted: nil) { _ in
          draggedPageID = nil
          return true
        }
      }
      .receiptBackground(style)
      .navigationTitle("Pages")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(role: .close) { dismiss() }
        }
      }
      .receiptBottomBar {
        GlassEffectContainer {
          if editor.needsRescan {
            rescanButton
          }
        }
        .animation(.glassMorph, value: editor.needsRescan)
      }
    }
    .tint(style.accentColor(for: colorScheme))
    .task(id: Set(editor.pages.map(\.id))) { await loadPageURLs() }
    .onChange(of: editor.pages.map(\.id), initial: true) { _, pageIDs in
      orderedPageIDs = pageIDs
    }
    .task(id: orderedPageIDs) { await saveOrder() }
    .onDisappear(perform: saveOrderBeforeClosing)
    .haptics(haptic)
    .quickLookPreview($previewURL, in: displayedPages.compactMap { pageURLs[$0.id] })
    .fullScreenCover(isPresented: $isScannerPresented) {
      ReceiptScannerView(
        onCapture: { scan in
          isScannerPresented = false
          addPages { scan.pages }
        },
        onCancel: { isScannerPresented = false },
        onFailure: { error in
          isScannerPresented = false
          errorDescription = error.localizedDescription
        }
      )
      .ignoresSafeArea()
    }
    .photosPicker(
      isPresented: $isPhotoPickerPresented,
      selection: $photoItems,
      maxSelectionCount: 8,
      selectionBehavior: .ordered,
      matching: .images
    )
    .onChange(of: photoItems) { _, items in
      guard !items.isEmpty else { return }
      photoItems = []
      addPages { await ReceiptPhotoImporter.pages(from: items) }
    }
    .errorAlert("Couldn’t Update Pages", message: $errorDescription)
  }

  private var footnote: String? {
    if editor.needsRescan {
      return rescanUnavailableReason ?? "Rescan to read the receipt from the updated pages."
    }
    if editor.pages.count > 1 { return "Touch and hold a page to reorder or delete it." }
    return nil
  }

  /// Why the receipt can't be rescanned right now, or `nil` when it can.
  private var rescanUnavailableReason: String? {
    switch recognitions.modelStatus {
    case .limitReached(let resetDate, _):
      let resumption = resetDate.map { DeferredReceiptRead.resumption(at: $0) } ?? "later"
      return
        "Today’s reading limit is reached. Rescan \(resumption), or edit the items to match the updated pages."
    case .unavailable(let reason):
      return "\(reason) Edit the items to match the updated pages."
    case .available, .approachingLimit:
      return nil
    }
  }

  private var displayedPages: [ReceiptDocument.Page] {
    let pagesByID = Dictionary(uniqueKeysWithValues: editor.pages.map { ($0.id, $0) })
    let ordered = orderedPageIDs.compactMap { pagesByID[$0] }
    return ordered.count == editor.pages.count ? ordered : editor.pages
  }

  private func pageTile(_ page: ReceiptDocument.Page, number: Int) -> some View {
    Button {
      previewURL = pageURLs[page.id]
    } label: {
      ReceiptPageThumbnail(url: pageURLs[page.id])
        .overlay(alignment: .bottomLeading) {
          Text(number, format: .number)
            .font(.caption.weight(.semibold).monospacedDigit())
            .frame(minWidth: 28, minHeight: 28)
            .background(.regularMaterial, in: .circle)
            .padding(8)
        }
    }
    .buttonStyle(.plain)
    .onDrag {
      draggedPageID = page.id
      return NSItemProvider(object: page.id.uuidString as NSString)
    }
    .onDrop(
      of: [.text],
      delegate: ReceiptPageDropDelegate(
        target: page.id,
        order: $orderedPageIDs,
        draggedPageID: $draggedPageID,
        onReorder: { haptic.play(.selection) })
    )
    .contextMenu {
      Button("Delete Page", systemImage: "trash", role: .destructive) {
        delete(page)
      }
      .disabled(editor.pages.count == 1)
    }
    .accessibilityLabel("Page \(number)")
    .accessibilityHint("Shows the full page")
  }

  private var addTile: some View {
    ReceiptPageTileShape()
      .fill(.ultraThinMaterial)
      .overlay {
        ReceiptPageTileShape()
          .strokeBorder(.tint, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
      }
      .aspectRatio(ReceiptPageThumbnail.aspectRatio, contentMode: .fit)
      .overlay {
        if isAddingPages {
          ProgressView()
        } else {
          VStack(spacing: 0) {
            addButton("Scan", systemImage: "document.viewfinder") {
              isScannerPresented = true
            }
            Rectangle()
              .fill(.tint.opacity(0.25))
              .frame(height: 1)
              .padding(.horizontal, 20)
            addButton("Photos", systemImage: "photo.on.rectangle.angled") {
              isPhotoPickerPresented = true
            }
          }
        }
      }
      .disabled(isAddingPages)
  }

  private func addButton(
    _ title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.title2.weight(.semibold))
        Text(title)
          .font(.subheadline.weight(.semibold))
      }
      .foregroundStyle(.tint)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
  }

  private var rescanButton: some View {
    ReceiptActionButton(
      title: "Rescan", systemImage: "arrow.clockwise", tint: style.prominentColor
    ) {
      isRescanConfirmationPresented = true
    }
    .disabled(rescanUnavailableReason != nil)
    .accessibilityHint("Reads the receipt again from the current pages")
    .confirmationDialog(
      "Rescan Receipt?",
      isPresented: $isRescanConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("Rescan") {
        dismiss()
        editor.rescan()
      }
    } message: {
      Text(
        "Items and totals are read again from these pages. People stay on the receipt, but item assignments are cleared."
      )
    }
  }

  private func addPages(_ pages: @escaping @MainActor () async -> [ReceiptPage]) {
    isAddingPages = true
    Task {
      defer { isAddingPages = false }
      let pages = await pages()
      guard !pages.isEmpty else {
        errorDescription = "The selected images could not be read. Select different images."
        return
      }
      do {
        try await editor.add(pages)
        haptic.play(.success)
      } catch {
        errorDescription = error.localizedDescription
      }
    }
  }

  private var hasUnsavedOrder: Bool {
    orderedPageIDs != editor.pages.map(\.id)
      && Set(orderedPageIDs) == Set(editor.pages.map(\.id))
  }

  /// Closing cancels the delayed save, so an order changed just before closing is saved here.
  private func saveOrderBeforeClosing() {
    guard hasUnsavedOrder else { return }
    let order = orderedPageIDs
    let reorder = editor.reorder
    Task { try? await reorder(order) }
  }

  private func saveOrder() async {
    guard hasUnsavedOrder else { return }
    do {
      try await Task.sleep(for: .milliseconds(400))
      try await editor.reorder(orderedPageIDs)
    } catch is CancellationError {
      return
    } catch {
      orderedPageIDs = editor.pages.map(\.id)
      errorDescription = error.localizedDescription
    }
  }

  private func delete(_ page: ReceiptDocument.Page) {
    Task {
      do {
        try await editor.delete(page.id)
        haptic.play(.removal)
      } catch {
        errorDescription = error.localizedDescription
      }
    }
  }

  private func loadPageURLs() async {
    do {
      let urls = try await storage.pageURLs(receiptID)
      let urlsByFilename = Dictionary(
        urls.map { ($0.lastPathComponent, $0) },
        uniquingKeysWith: { first, _ in first })
      pageURLs = Dictionary(
        uniqueKeysWithValues: editor.pages.compactMap { page in
          urlsByFilename[URL(filePath: page.file).lastPathComponent].map { (page.id, $0) }
        })
    } catch {
      errorDescription = error.localizedDescription
    }
  }
}

private struct ReceiptPageDropDelegate: DropDelegate {
  let target: ReceiptDocument.Page.ID
  @Binding var order: [ReceiptDocument.Page.ID]
  @Binding var draggedPageID: ReceiptDocument.Page.ID?
  let onReorder: () -> Void

  func dropEntered(info: DropInfo) {
    guard let draggedPageID, draggedPageID != target,
      let source = order.firstIndex(of: draggedPageID),
      let destination = order.firstIndex(of: target)
    else { return }
    withAnimation(.smooth(duration: 0.25)) {
      order.move(
        fromOffsets: IndexSet(integer: source),
        toOffset: destination > source ? destination + 1 : destination)
    }
    onReorder()
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    draggedPageID = nil
    return true
  }
}

private struct ReceiptPageTileShape: InsettableShape {
  var inset: CGFloat = 0

  func path(in rect: CGRect) -> Path {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
      .inset(by: inset)
      .path(in: rect)
  }

  func inset(by amount: CGFloat) -> ReceiptPageTileShape {
    ReceiptPageTileShape(inset: inset + amount)
  }
}

private struct ReceiptPageThumbnail: View {
  static let aspectRatio: CGFloat = 0.72

  let url: URL?
  @State private var image: CGImage?

  var body: some View {
    ReceiptPageTileShape()
      .fill(.background.secondary)
      .aspectRatio(Self.aspectRatio, contentMode: .fit)
      .overlay {
        if let image {
          Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
        } else {
          ProgressView()
        }
      }
      .clipShape(ReceiptPageTileShape())
      .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
      .animation(.smooth(duration: 0.25), value: image != nil)
      .task(id: url) {
        guard let url else { return }
        image = await Self.thumbnail(for: url)
      }
  }

  private static func thumbnail(for url: URL) async -> CGImage? {
    await Task.detached(priority: .userInitiated) {
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
      let options =
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 600,
        ] as CFDictionary
      return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }.value
  }
}
