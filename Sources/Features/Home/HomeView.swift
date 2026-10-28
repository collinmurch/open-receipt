import SwiftUI

/// A screen pushed from the receipt library.
enum HomeRoute: Hashable {
  /// A receipt, zooming out of the library control that opened it, if any.
  case receipt(ReceiptFlowInput, zoomingFrom: HomeZoomSource? = nil)
  case people
  case settings
  case recentlyDeleted
}

/// A control in the receipt library that a pushed screen zooms out of.
enum HomeZoomSource: Hashable {
  case row(ReceiptLibraryRowID)
  case newReceipt
}

/// A receipt's row in the library. A receipt opened lately has one in Recently Opened as well as
/// one in its month.
struct ReceiptLibraryRowID: Hashable {
  let receiptID: UUID
  var isRecent = false
}

struct HomeView: View {
  @State private var path: [HomeRoute] = []
  @State private var isScannerPresented = false
  @State private var cameraErrorDescription: String?
  @State private var requestedSource: NewReceiptSource?
  @State private var libraryHaptic = HapticEvent()
  @Namespace private var libraryTransition
  @Environment(ReceiptLibraryModel.self) private var library
  @Environment(ReceiptRecognitionCenter.self) private var recognitions
  @Environment(NewReceiptQuickActions.self) private var quickActions: NewReceiptQuickActions?
  @Environment(\.peopleStorage) private var peopleStorage
  @Environment(\.scenePhase) private var scenePhase

  init(initialPath: [HomeRoute] = []) {
    _path = State(initialValue: initialPath)
  }

  var body: some View {
    NavigationStack(path: $path) {
      ReceiptLibraryView(
        transitionNamespace: libraryTransition,
        onScan: presentScanner,
        onOpen: { path.append($0) },
        requestedSource: $requestedSource,
        haptic: $libraryHaptic
      )
      .navigationDestination(for: HomeRoute.self) { destination(for: $0) }
    }
    .haptics(libraryHaptic)
    .fullScreenCover(isPresented: $isScannerPresented) {
      ReceiptScannerView(
        onCapture: capture,
        onCancel: { isScannerPresented = false },
        onFailure: { error in
          isScannerPresented = false
          cameraErrorDescription = error.localizedDescription
        }
      )
      .ignoresSafeArea()
    }
    .errorAlert("Couldn’t Open Camera", message: $cameraErrorDescription)
    .environment(\.receiptLibraryRefresh, ReceiptLibraryRefreshAction(library: library))
    .task {
      await library.load()
      await recognitions.resumeDeferredReads()
    }
    .onChange(of: quickActions?.pending, initial: true) { _, source in
      guard let source else { return }
      quickActions?.pending = nil
      returnToLibrary(for: source)
      requestedSource = source
    }
    .onChange(of: recognitions.finishedCount) {
      Task { await library.load() }
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      Task {
        await library.refreshTrashIfNeeded()
        await recognitions.resumeDeferredReads()
      }
    }
  }

  @ViewBuilder
  private func destination(for route: HomeRoute) -> some View {
    switch route {
    case .receipt(let input, let source):
      ReceiptFlowView(input: input)
        .zoomTransition(from: source, in: libraryTransition)
        // An interactive zoom back to the library only reshows a hidden toolbar once its spring
        // settles, so the library's search and new receipt button lag. Keeping the empty bar up
        // lets them swap in with the transition instead.
        .toolbarVisibility(.visible, for: .bottomBar)
    case .people:
      PeopleView(storage: peopleStorage)
    case .settings:
      SettingsView()
    case .recentlyDeleted:
      ReceiptTrashView(onOpen: { path.append($0) })
    }
  }

  private func presentScanner() {
    recognitions.prewarm()
    isScannerPresented = true
  }

  /// A quick action starts its receipt from the library, so whatever is open closes first. An
  /// open scanner stays up for Scan.
  private func returnToLibrary(for source: NewReceiptSource) {
    withTransaction(\.disablesAnimations, true) {
      path = []
    }
    if source != .scan { isScannerPresented = false }
  }

  /// Reading starts as soon as the scan exists, unless the model is unavailable. The receipt is
  /// pushed under the scanner, so closing the scanner reveals it without a second transition.
  private func capture(_ scan: ReceiptScan) {
    let input = ReceiptFlowInput.scan(scan, recognitions: recognitions)
    withTransaction(\.disablesAnimations, true) {
      path.append(.receipt(input))
    }
    isScannerPresented = false
  }
}

extension View {
  @ViewBuilder
  fileprivate func zoomTransition(from source: HomeZoomSource?, in namespace: Namespace.ID)
    -> some View
  {
    if let source {
      navigationTransition(.zoom(sourceID: source, in: namespace))
    } else {
      self
    }
  }
}

#Preview {
  HomeView()
    .environment(ReceiptLibraryModel(storage: .live, recents: .live))
    .environment(
      ReceiptRecognitionCenter(parsingClient: .standard, storage: .live, access: .unlimited())
    )
    .environment(ReadingAccess.unlimited())
}
