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
  @State private var deletionCount = 0
  @State private var openingReceiptID: ReceiptSummary.ID?
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
    .animation(.smooth(duration: 0.3), value: sections)
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
    .sensoryFeedback(.removal, trigger: deletionCount)
    .errorAlert("Couldn’t Update Receipts", message: $library.errorDescription) {
      Button("Retry") { Task { await library.load() } }
      Button("OK", role: .cancel) {}
    }
    .errorAlert("Couldn’t Import Receipt", message: $importErrorDescription)
  }

  @ToolbarContentBuilder
  private var libraryToolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      Button("People", systemImage: "person.2") { onOpen(.people) }
      Button("Settings", systemImage: "gearshape") { onOpen(.settings) }
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
    .disabled(isImporting)
    .animation(.smooth(duration: 0.2), value: isImporting)
  }

  @ViewBuilder
  private func row(for receipt: ReceiptSummary) -> some View {
    let recognition = recognitions.recognition(for: receipt.id)
    if receipt.isUnavailable {
      ReceiptLibraryRow(receipt: receipt)
    } else {
      Button {
        open(receipt)
      } label: {
        ReceiptLibraryRow(
          receipt: receipt,
          recognition: recognition,
          transition: (id: HomeZoomSource.row(receipt.id), namespace: transitionNamespace))
      }
      .tint(.primary)
      .screenshotHighlight("library-row-\(receipt.merchantName ?? "")")
      .contextMenu {
        Button("Delete Receipt", systemImage: "trash", role: .destructive) {
          delete(receipt)
        }
      }
    }
  }

  /// Opens a receipt once its document has loaded, so the receipt is complete on the transition's
  /// first frame.
  private func open(_ receipt: ReceiptSummary) {
    guard openingReceiptID == nil else { return }
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
    deletionCount += 1
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

/// The first-run screen, shown until the library has a receipt.
private struct ReceiptLibraryEmptyState: View {
  @State private var hasAppeared = false

  var body: some View {
    ContentUnavailableView {
      VStack(spacing: 16) {
        Image(systemName: "receipt")
          .font(.system(size: 58))
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
