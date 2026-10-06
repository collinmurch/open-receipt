import PhotosUI
import SwiftUI

/// The receipt library, and the app's root screen. New receipts start from the bottom toolbar.
struct ReceiptLibraryView: View {
  let transitionNamespace: Namespace.ID
  let onScan: () -> Void
  let onOpen: (HomeRoute) -> Void
  @State private var searchText = ""
  @State private var isSearchPresented = false
  @FocusState private var isSearchFocused: Bool
  /// Whether the new receipt button stays a close button under search after the chooser faded
  /// for it, so it turns back while search hides it rather than as search covers it.
  @State private var holdsCloseUnderSearch = false
  @State private var chooserPhase = NewReceiptChooserPhase.hidden
  @State private var importedItems: [PhotosPickerItem] = []
  @State private var isPhotoPickerPresented = false
  @State private var isImporting = false
  @State private var importErrorDescription: String?
  @State private var openingReceiptID: ReceiptSummary.ID?
  @State private var focusedID: ReceiptSummary.ID?
  @State private var focusedRowFrame: CGRect?
  @State private var haptic = HapticEvent()
  @State private var riseCount = 0
  @State private var isUnlockPresented = false
  @Environment(ReceiptLibraryModel.self) private var library
  @Environment(ReceiptRecognitionCenter.self) private var recognitions
  @Environment(ReadingAccess.self) private var access
  @Environment(\.receiptStorageClient) private var storage

  var body: some View {
    @Bindable var library = library
    let query = searchQuery
    let allSections = librarySections(reading: readingReceipts)
    let sections = query.isEmpty ? allSections : filtered(allSections, matching: query)

    List {
      if recognitions.modelStatus != .available {
        Section {
          ReceiptModelNotice(
            status: recognitions.modelStatus,
            onIncreaseLimit: recognitions.showLimitIncrease)
        }
      }

      if !access.isUnlocked, access.freeReadsLeft < ReadingAccess.freeReadLimit {
        Section {
          FreeReadsNotice { isUnlockPresented = true }
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
    .background { AppBackground() }
    .overlay {
      if library.hasLoaded, sections.isEmpty {
        if query.isEmpty {
          ReceiptLibraryEmptyState()
        } else {
          ContentUnavailableView.search(text: query)
        }
      }
    }
    // Search results update as they're typed and as search closes, like the system's, so only
    // changes to the library itself animate.
    .animation(.smooth(duration: 0.3), value: allSections)
    .gesture(
      ListBackgroundTapGesture(
        isEnabled: isSearchPresented && !isFocusing,
        onTap: lowerSearch
      )
    )
    .overlay { libraryFocus(in: sections) }
    .overlay { newReceiptChooser }
    .navigationTitle("Receipts")
    .buildChannelSubtitle()
    .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search receipts")
    .searchFocused($isSearchFocused)
    .toolbar { libraryToolbar }
    .toolbarVisibility(isFocusing ? .hidden : .automatic, for: .bottomBar)
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
    .onChange(of: isSearchPresented) { _, isPresented in
      if isPresented {
        // Search's own expansion is the only motion in the bottom bar, so the chooser fades.
        guard chooserPhase.isRaised else { return }
        chooserPhase = .fading
        holdsCloseUnderSearch = true
      } else {
        holdsCloseUnderSearch = false
      }
    }
    .haptics(haptic)
    .errorAlert("Couldn’t Update Receipts", message: $library.errorDescription) {
      Button("Retry") { Task { await library.load() } }
      Button("OK", role: .cancel) {}
    }
    .errorAlert("Couldn’t Import Receipt", message: $importErrorDescription)
    .unlimitedReadingSheet(isPresented: $isUnlockPresented)
  }

  @ToolbarContentBuilder
  private var libraryToolbar: some ToolbarContent {
    if !isFocusing {
      // Disabled rather than removed while choosing: rebuilding the toolbar as search activates
      // takes the search field's focus.
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("People", systemImage: "person.2") { onOpen(.people) }
          .disabled(isChoosingSource)
        Button("Settings", systemImage: "gearshape") { onOpen(.settings) }
          .disabled(isChoosingSource)
      }
    }

    DefaultToolbarItem(kind: .search, placement: .bottomBar)
    ToolbarSpacer(.flexible, placement: .bottomBar)
    ToolbarItem(placement: .bottomBar) {
      newReceiptButton
    }
    .matchedTransitionSource(id: HomeZoomSource.newReceipt, in: transitionNamespace)
  }

  /// Raises the ways to start a receipt, and turns into a close button while they're up.
  private var newReceiptButton: some View {
    Button {
      toggleChooser()
    } label: {
      if isImporting {
        ProgressView()
          .transition(.opacity)
      } else {
        Label(showsClose ? "Close" : "New Receipt", systemImage: "plus")
          .rotationEffect(.degrees(showsClose ? 45 : 0))
          // Without a chooser, the button only turns back as search hides it, so without a spin.
          .animation(chooserPhase == .hidden ? nil : .choiceToggle, value: showsClose)
          .transition(.opacity)
      }
    }
    .buttonStyle(.glassProminent)
    .sensoryFeedback(.rise, trigger: riseCount)
    .disabled(isImporting || isFocusing)
    .animation(.smooth(duration: 0.2), value: isImporting)
  }

  @ViewBuilder
  private var newReceiptChooser: some View {
    if chooserPhase != .hidden {
      NewReceiptChooser(
        phase: chooserPhase,
        onChoose: choose,
        onDismiss: { chooserPhase = .dropping(pending: nil) },
        onFinish: { pending in
          chooserPhase = .hidden
          if let pending { start(from: pending) }
        }
      )
    }
  }

  private var isChoosingSource: Bool { chooserPhase.isRaised }

  private var showsClose: Bool { isChoosingSource || holdsCloseUnderSearch }

  private func toggleChooser() {
    if chooserPhase.isRaised {
      chooserPhase = .dropping(pending: nil)
    } else {
      riseCount += 1
      chooserPhase = .raised
    }
  }

  /// The camera and photo picker cover the screen, so they open at once while the chooser drops
  /// beneath them. Create zooms out of the new receipt button, so it waits for the drop.
  private func choose(_ source: NewReceiptSource) {
    switch source {
    case .scan, .importPhotos:
      start(from: source)
      chooserPhase = .dropping(pending: nil)
    case .create:
      chooserPhase = .dropping(pending: source)
    }
  }

  private func start(from source: NewReceiptSource) {
    switch source {
    case .scan:
      onScan()
    case .importPhotos:
      recognitions.prewarm()
      isPhotoPickerPresented = true
    case .create:
      onOpen(.receipt(.create(), zoomingFrom: .newReceipt))
    }
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
      onFocus: { focus(receipt) },
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
        startsPressed: true,
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

  private func focus(_ receipt: ReceiptSummary) {
    guard !isFocusing else { return }
    haptic.play(.lift)
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

  /// Lowers the keyboard, keeping any results on screen, or closes search once there's nothing
  /// left to lower.
  private func lowerSearch() {
    if isSearchFocused, !searchQuery.isEmpty {
      isSearchFocused = false
    } else {
      isSearchPresented = false
    }
  }

  private var searchQuery: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// New receipts being read that storage has not listed yet, newest first.
  private var readingReceipts: [ReceiptSummary] {
    guard !recognitions.recognitions.isEmpty else { return [] }
    let storedIDs = Set(library.receipts.map(\.id))
    return recognitions.recognitions.values
      .filter { !$0.isRescan && !storedIDs.contains($0.id) }
      .sorted { $0.capturedAt > $1.capturedAt }
      .map {
        ReceiptSummary.reading(
          id: $0.id, capturedAt: $0.capturedAt, backgroundStyle: $0.backgroundStyle)
      }
  }

  /// The library's sections with `reading` merged in.
  private func librarySections(reading: [ReceiptSummary]) -> [ReceiptLibrarySection] {
    reading.isEmpty
      ? library.sections : ReceiptLibrarySections.grouped(reading + library.receipts)
  }

  /// `sections` narrowed to `query`. Reading a streaming merchant name here redraws the list as it
  /// streams, so it is read only while searching.
  private func filtered(
    _ sections: [ReceiptLibrarySection],
    matching query: String
  ) -> [ReceiptLibrarySection] {
    ReceiptLibrarySections.filtered(sections) { receipt in
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
      importErrorDescription = "The selected images couldn’t be opened. Select different images."
      return
    }
    let scan = ReceiptScan(pages: pages, source: .photoLibrary)
    onOpen(.receipt(.scan(scan, recognitions: recognitions), zoomingFrom: .newReceipt))
  }
}

/// A receipt in the library. A long press lifts it into focus.
private struct ReceiptLibraryListRow: View {
  let receipt: ReceiptSummary
  let recognition: ReceiptRecognition?
  let transition: (id: HomeZoomSource, namespace: Namespace.ID)?
  let isFocused: Bool
  let isLiftedOut: Bool
  let onTap: () -> Void
  let onFocus: () -> Void
  let onDelete: () -> Void
  let onFocusedFrameChange: (CGRect) -> Void

  var body: some View {
    ReceiptLibraryRow(receipt: receipt, recognition: recognition, transition: transition)
      .liftableRow(
        isFocused: isFocused,
        isLiftedOut: isLiftedOut,
        onTap: onTap,
        onLongPress: onFocus,
        onFocusedFrameChange: onFocusedFrameChange
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

extension Animation {
  /// The new receipt button turning between a plus and a close button.
  fileprivate static let choiceToggle = Animation.spring(duration: 0.4, bounce: 0.3)
}
