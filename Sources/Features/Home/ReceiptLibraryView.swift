import PhotosUI
import SwiftUI

/// The receipt library, and the app's root screen. New receipts start from the bottom toolbar.
struct ReceiptLibraryView: View {
  let transitionNamespace: Namespace.ID
  let onScan: () -> Void
  let onOpen: (HomeRoute) -> Void
  @State private var searchText = ""
  @State private var importedItems: [PhotosPickerItem] = []
  @State private var isPhotoPickerPresented = false
  @State private var isImporting = false
  @State private var importErrorDescription: String?
  @State private var openingReceiptID: ReceiptSummary.ID?
  @State private var focusedID: ReceiptSummary.ID?
  @State private var focusedRowFrame: CGRect?
  @State private var isFocusedRowPressed = false
  @State private var haptic = HapticEvent()
  @Environment(ReceiptLibraryModel.self) private var library
  @Environment(ReceiptRecognitionCenter.self) private var recognitions
  @Environment(\.receiptStorageClient) private var storage

  var body: some View {
    @Bindable var library = library
    let reading = readingReceipts
    let query = searchQuery
    let sections = displayedSections(reading: reading, query: query)

    List {
      if recognitions.modelStatus != .available {
        Section {
          ReceiptModelNotice(
            status: recognitions.modelStatus,
            onIncreaseLimit: recognitions.showLimitIncrease)
        }
      }

      ForEach(sections) { section in
        Section {
          ForEach(section.receipts) { receipt in
            row(for: receipt)
          }
          .onDelete { offsets in
            for index in offsets where section.receipts.indices.contains(index) {
              delete(section.receipts[index])
            }
          }
        } header: {
          Text(section.title)
        }
      }

      if query.isEmpty, !library.deletedReceipts.isEmpty {
        Section {
          NavigationLink(value: HomeRoute.recentlyDeleted) {
            Label("Recently Deleted", systemImage: "trash")
          }
        }
      }
    }
    .headerProminence(.increased)
    .scrollContentBackground(.hidden)
    .background { ReceiptLibraryBackground() }
    .overlay {
      if library.hasLoaded, sections.isEmpty {
        if query.isEmpty {
          ReceiptLibraryEmptyState()
        } else {
          ContentUnavailableView.search(text: query)
        }
      }
    }
    // Search results update as they're typed, like the system's, rather than animating.
    .animation(query.isEmpty ? .smooth(duration: 0.3) : nil, value: sections)
    .overlay { libraryFocus(in: sections) }
    .navigationTitle("Receipts")
    .debugBuildSubtitle()
    .searchable(text: $searchText, prompt: "Search receipts")
    .toolbar { libraryToolbar }
    .photosPicker(
      isPresented: $isPhotoPickerPresented,
      selection: $importedItems,
      maxSelectionCount: 8,
      selectionBehavior: .ordered,
      matching: .images
    )
    .onChange(of: importedItems) { _, items in
      Task { await importImages(items) }
    }
    .onChange(of: library.receipts) { _, receipts in
      // A receipt still being read isn't stored yet, so only its read ending can remove it.
      guard let focusedID, recognitions.recognition(for: focusedID) == nil else { return }
      if !receipts.contains(where: { $0.id == focusedID }) { endFocus() }
    }
    .onChange(of: searchText) {
      if focusedID != nil { endFocus() }
    }
    .haptics(haptic)
    .errorAlert("Couldn’t Update Receipts", message: $library.errorDescription) {
      Button("Retry") { Task { await library.load() } }
      Button("OK", role: .cancel) {}
    }
    .errorAlert("Couldn’t Import Receipt", message: $importErrorDescription)
  }

  @ToolbarContentBuilder
  private var libraryToolbar: some ToolbarContent {
    if !isFocusing {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("People", systemImage: "person.2") { onOpen(.people) }
        Button("Settings", systemImage: "gearshape") { onOpen(.settings) }
      }
    }

    DefaultToolbarItem(kind: .search, placement: .bottomBar)
    ToolbarSpacer(.flexible, placement: .bottomBar)
    ToolbarItem(placement: .bottomBar) {
      newReceiptMenu
    }
    .matchedTransitionSource(id: HomeZoomSource.newReceipt, in: transitionNamespace)
  }

  private var newReceiptMenu: some View {
    Menu {
      Button("Scan", systemImage: "document.viewfinder", action: onScan)
      Button("Import", systemImage: "photo.on.rectangle.angled") {
        recognitions.prewarm()
        isPhotoPickerPresented = true
      }
      Button("Create", systemImage: "square.and.pencil") {
        onOpen(.receipt(.create(), zoomingFrom: .newReceipt))
      }
    } label: {
      if isImporting {
        ProgressView()
          .transition(.opacity)
      } else {
        Label("New Receipt", systemImage: "plus")
          .transition(.opacity)
      }
    }
    .buttonStyle(.glassProminent)
    .disabled(isImporting || isFocusing)
    .animation(.smooth(duration: 0.2), value: isImporting)
  }

  private func row(for receipt: ReceiptSummary) -> some View {
    let isFocused = receipt.id == focusedID
    return ReceiptLibraryListRow(
      receipt: receipt,
      recognition: recognitions.recognition(for: receipt.id),
      transition: receipt.isUnavailable
        ? nil : (id: HomeZoomSource.row(receipt.id), namespace: transitionNamespace),
      isFocused: isFocused,
      isLiftedOut: isFocused && focusedRowFrame != nil,
      onTap: { open(receipt) },
      onFocus: { focus(receipt, isPressed: $0) },
      onDelete: { delete(receipt) },
      onFocusedFrameChange: { focusedRowFrame = $0 }
    )
    .screenshotHighlight("library-row-\(receipt.merchantName ?? "")")
  }

  @ViewBuilder
  private func libraryFocus(in sections: [ReceiptLibrarySection]) -> some View {
    if let focusedID, let focusedRowFrame,
      let receipt = sections.lazy.flatMap(\.receipts).first(where: { $0.id == focusedID })
    {
      ReceiptRowFocusView(
        row: ReceiptLibraryRow(
          receipt: receipt, recognition: recognitions.recognition(for: receipt.id)),
        rowFrame: focusedRowFrame,
        startsPressed: isFocusedRowPressed,
        primaryAction: receipt.isUnavailable
          ? nil
          : .init(title: "Open", systemImage: "arrow.up.forward") { open(receipt) },
        primaryTint: receipt.backgroundStyle.prominentColor,
        deleteAction: .init(title: "Delete", systemImage: "trash") { delete(receipt) },
        onDismiss: endFocus
      )
      // The focus view animates its own arrival, starting over the row it copies.
      .transition(.identity)
    }
  }

  private var isFocusing: Bool { focusedID != nil }

  private func focus(_ receipt: ReceiptSummary, isPressed: Bool) {
    guard !isFocusing else { return }
    haptic.play(.lift)
    isFocusedRowPressed = isPressed
    withAnimation(.settle) {
      focusedID = receipt.id
    }
  }

  private func endFocus() {
    withAnimation(.settle) {
      focusedID = nil
      focusedRowFrame = nil
    }
  }

  /// Opens a receipt once its document has loaded, so the receipt is complete on the transition's
  /// first frame.
  private func open(_ receipt: ReceiptSummary) {
    guard !receipt.isUnavailable, openingReceiptID == nil else { return }
    if let recognition = recognitions.recognition(for: receipt.id) {
      onOpen(.receipt(.recognition(recognition), zoomingFrom: .row(receipt.id)))
      return
    }
    openingReceiptID = receipt.id
    Task {
      defer { openingReceiptID = nil }
      let document = try? await storage.load(receipt.id)
      let input = ReceiptFlowInput.storedReceipt(
        receipt.id, backgroundStyle: receipt.backgroundStyle, document: document)
      onOpen(.receipt(input, zoomingFrom: .row(receipt.id)))
    }
  }

  private var searchQuery: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// New receipts being read that storage has not listed yet, newest first.
  private var readingReceipts: [ReceiptSummary] {
    let storedIDs = Set(library.receipts.map(\.id))
    return recognitions.recognitions.values
      .filter { !$0.isRescan && !storedIDs.contains($0.id) }
      .sorted { $0.capturedAt > $1.capturedAt }
      .map {
        ReceiptSummary.reading(
          id: $0.id, capturedAt: $0.capturedAt, backgroundStyle: $0.backgroundStyle)
      }
  }

  /// The library's sections with `reading` merged in and narrowed to `query`. Reading a streaming
  /// merchant name here redraws the list as it streams, so it is read only while searching.
  private func displayedSections(
    reading: [ReceiptSummary],
    query: String
  ) -> [ReceiptLibrarySection] {
    let sections =
      reading.isEmpty
      ? library.sections : ReceiptLibrarySections.grouped(reading + library.receipts)
    guard !query.isEmpty else { return sections }
    return ReceiptLibrarySections.filtered(sections) { receipt in
      [
        receipt.merchantName,
        recognitions.recognition(for: receipt.id)?.preview.merchantName,
        receipt.localDate,
        receipt.currency,
        receipt.localDate.flatMap { ReceiptLibraryDateFormatter.formatted(localDate: $0) },
      ]
      .compactMap { $0 }
      .contains { $0.localizedCaseInsensitiveContains(query) }
    }
  }

  /// Deletes `receipt`, first stopping a read of it that is in progress.
  private func delete(_ receipt: ReceiptSummary) {
    haptic.play(.removal)
    let recognition = recognitions.recognition(for: receipt.id)
    Task {
      if let recognition { await recognitions.cancel(recognition) }
      await library.delete(receipt)
    }
  }

  private func importImages(_ items: [PhotosPickerItem]) async {
    guard !items.isEmpty else { return }
    isImporting = true
    defer {
      isImporting = false
      importedItems = []
    }
    let pages = await ReceiptPhotoImporter.pages(from: items)
    guard !pages.isEmpty else {
      importErrorDescription = "The selected images could not be read. Select different images."
      return
    }
    let scan = ReceiptScan(pages: pages, source: .photoLibrary)
    onOpen(.receipt(.scan(scan, recognitions: recognitions), zoomingFrom: .newReceipt))
  }
}

/// A receipt in the library. Taps and long presses are one gesture rather than a button or a
/// context menu, as receipt items are, so a long press lifts the receipt into focus.
private struct ReceiptLibraryListRow: View {
  let receipt: ReceiptSummary
  let recognition: ReceiptRecognition?
  let transition: (id: HomeZoomSource, namespace: Namespace.ID)?
  let isFocused: Bool
  let isLiftedOut: Bool
  let onTap: () -> Void
  let onFocus: (_ isPressed: Bool) -> Void
  let onDelete: () -> Void
  let onFocusedFrameChange: (CGRect) -> Void

  @State private var isPressed = false

  var body: some View {
    ReceiptLibraryRow(receipt: receipt, recognition: recognition, transition: transition)
      .onGeometryChange(for: CGRect?.self) { proxy in
        isFocused ? proxy.frame(in: .global) : nil
      } action: { frame in
        if let frame { onFocusedFrameChange(frame) }
      }
      .pressScale(isPressed)
      // The focused copy stands in for the row, so the row hides and returns in one frame.
      .opacity(isLiftedOut ? 0 : 1)
      .transaction(value: isLiftedOut) { $0.animation = nil }
      .contentShape(.rect)
      .gesture(
        ReceiptRowPressGesture(
          onPressingChanged: { isPressed = $0 },
          onTap: onTap,
          onLongPress: { onFocus(true) }
        )
      )
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(receipt.isUnavailable ? [] : .isButton)
      .accessibilityAction(.default, onTap)
      .accessibilityHint(receipt.isUnavailable ? Text("") : Text("Opens the receipt"))
      .accessibilityActions {
        Button("Delete Receipt", role: .destructive, action: onDelete)
      }
  }
}

/// The first-run screen, shown until the library has a receipt.
private struct ReceiptLibraryEmptyState: View {
  @State private var hasAppeared = false
  @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 58

  var body: some View {
    ContentUnavailableView {
      VStack(spacing: 16) {
        Image(systemName: "receipt")
          .font(.system(size: iconSize))
          .foregroundStyle(.tint)
          .symbolEffect(.bounce, value: hasAppeared)
        VStack(spacing: 4) {
          Text("Open Receipt")
            .font(.largeTitle.bold())
          Text("Scan. Split. Settle.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    } description: {
      Text("Tap \(Image(systemName: "plus")) to add your first receipt.")
        .padding(.top, 20)
    }
    .onAppear { hasAppeared = true }
  }
}

/// Persistent status for receipt reading, shown before a person scans rather than after.
private struct ReceiptModelNotice: View {
  let status: ReceiptModelStatus
  let onIncreaseLimit: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(message, systemImage: systemImage)
        .font(.footnote)
        .foregroundStyle(.secondary)
      if canIncreaseLimit {
        Button("Increase Limit", action: onIncreaseLimit)
          .font(.footnote.weight(.semibold))
      }
    }
  }

  private var message: String {
    switch status {
    case .available:
      return ""
    case .approachingLimit:
      return "You’re close to today’s limit for reading receipts."
    case .limitReached(let resetDate, _):
      let resumption = resetDate.map { DeferredReceiptRead.resumption(at: $0) } ?? "later"
      return
        "Today’s reading limit is reached. New scans are saved and read automatically \(resumption)."
    case .unavailable(let reason):
      return "\(reason) You can still enter receipts manually."
    }
  }

  private var systemImage: String {
    switch status {
    case .available, .approachingLimit: "gauge.with.dots.needle.67percent"
    case .limitReached: "hourglass"
    case .unavailable: "exclamationmark.triangle"
    }
  }

  private var canIncreaseLimit: Bool {
    switch status {
    case .approachingLimit(let canIncreaseLimit), .limitReached(_, let canIncreaseLimit):
      canIncreaseLimit
    case .available, .unavailable:
      false
    }
  }
}
