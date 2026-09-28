import PhotosUI
import SwiftUI

struct NewReceiptView: View {
  let onScan: () -> Void
  let onRecognize: (ReceiptScan) -> Void
  let onCreate: () -> Void
  @State private var importedItems: [PhotosPickerItem] = []
  @State private var isPhotoPickerPresented = false
  @State private var isImporting = false
  @State private var importErrorDescription: String?
  @Environment(ReceiptRecognitionCenter.self) private var recognitions

  var body: some View {
    VStack(spacing: 20) {
      ReceiptHeroTitle()

      Menu {
        Button(action: onScan) {
          Label("Scan", systemImage: "document.viewfinder")
        }

        Button {
          recognitions.prewarm()
          isPhotoPickerPresented = true
        } label: {
          Label("Import", systemImage: "photo.on.rectangle.angled")
        }
        .disabled(isImporting)

        Button(action: onCreate) {
          Label("Create", systemImage: "square.and.pencil")
        }
      } label: {
        Label("New", systemImage: "plus")
          .font(.title3.weight(.semibold))
          .padding(.horizontal, 24)
      }
      .buttonStyle(.glassProminent)
      .buttonBorderShape(.capsule)
      .controlSize(.large)
      .disabled(isImporting)

      if isImporting {
        ProgressView("Importing receipt")
          .font(.caption)
          .transition(.opacity)
      }

      ReceiptModelNotice(
        status: recognitions.modelStatus,
        onIncreaseLimit: recognitions.showLimitIncrease)
    }
    .frame(maxWidth: .infinity)
    .errorHaptic(importErrorDescription)
    .onChange(of: importedItems) { _, items in
      Task { await importImages(items) }
    }
    .photosPicker(
      isPresented: $isPhotoPickerPresented,
      selection: $importedItems,
      maxSelectionCount: 8,
      selectionBehavior: .ordered,
      matching: .images
    )
    .alert(
      "Couldn’t Import Receipt",
      isPresented: Binding(
        get: { importErrorDescription != nil },
        set: { if !$0 { importErrorDescription = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(importErrorDescription ?? "The selected images could not be imported.")
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
    onRecognize(ReceiptScan(pages: pages, source: .photoLibrary))
  }
}

/// Persistent status for receipt reading, shown before a person scans rather than after.
private struct ReceiptModelNotice: View {
  let status: ReceiptModelStatus
  let onIncreaseLimit: () -> Void

  var body: some View {
    if let message {
      VStack(spacing: 8) {
        Label(message, systemImage: systemImage)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        if canIncreaseLimit {
          Button("Increase Limit", action: onIncreaseLimit)
            .font(.footnote.weight(.semibold))
        }
      }
      .transition(.opacity)
    }
  }

  private var message: String? {
    switch status {
    case .available:
      return nil
    case .approachingLimit:
      return "You’re close to today’s limit for reading receipts."
    case .limitReached(let resetDate, _):
      guard let resetDate, resetDate > .now else {
        return "Today’s reading limit is reached. \(Self.savedForLater) later."
      }
      let time = resetDate.formatted(date: .omitted, time: .shortened)
      return "Today’s reading limit is reached. \(Self.savedForLater) after \(time)."
    case .unavailable(let reason):
      return "\(reason) You can still enter receipts manually."
    }
  }

  private static let savedForLater = "New scans are saved and can be read"

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

private struct ReceiptHeroTitle: View {
  @State private var hasAppeared = false

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "receipt")
        .font(.system(size: 58))
        .foregroundStyle(.tint)
        .symbolEffect(.bounce, value: hasAppeared)

      Text("Open Receipt")
        .font(.largeTitle.bold())

      Text("Scan. Split. Settle.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      #if DEBUG
        Text("Debug build")
          .font(.caption2.weight(.semibold))
          .textCase(.uppercase)
          .foregroundStyle(.orange)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(.thinMaterial, in: .capsule)
      #endif
    }
    .onAppear { hasAppeared = true }
  }
}
