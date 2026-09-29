import SwiftUI

/// A screen pushed from the receipt library.
enum HomeRoute: Hashable {
  /// A receipt. Receipts opened from a library row zoom out of that row.
  case receipt(ReceiptFlowInput, zoomsFromRow: Bool = false)
  case people
  case settings
  case recentlyDeleted
}

struct HomeView: View {
  @State private var path: [HomeRoute] = []
  @State private var isScannerPresented = false
  @State private var scanErrorDescription: String?
  @Namespace private var receiptTransition
  @Environment(ReceiptLibraryModel.self) private var library
  @Environment(ReceiptRecognitionCenter.self) private var recognitions
  @Environment(\.peopleStorageClient) private var peopleStorage
  @Environment(\.scenePhase) private var scenePhase

  init(initialPath: [HomeRoute] = []) {
    _path = State(initialValue: initialPath)
  }

  var body: some View {
    NavigationStack(path: $path) {
      ReceiptLibraryView(
        transitionNamespace: receiptTransition,
        onScan: presentScanner,
        onOpen: { path.append($0) }
      )
      .navigationDestination(for: HomeRoute.self) { destination(for: $0) }
    }
    .fullScreenCover(isPresented: $isScannerPresented) {
      ReceiptScannerView(
        onCapture: capture,
        onCancel: { isScannerPresented = false },
        onFailure: { error in
          isScannerPresented = false
          scanErrorDescription = error.localizedDescription
        }
      )
      .ignoresSafeArea()
    }
    .errorAlert("Couldn’t Scan Receipt", message: $scanErrorDescription)
    .environment(\.receiptLibraryRefresh, ReceiptLibraryRefreshAction(library: library))
    .task {
      await library.load()
      await recognitions.resumeDeferredReads()
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
    case .receipt(let input, let zoomsFromRow):
      if zoomsFromRow {
        ReceiptFlowView(input: input)
          .navigationTransition(.zoom(sourceID: input.id, in: receiptTransition))
      } else {
        ReceiptFlowView(input: input)
      }
    case .people:
      PeopleView(storage: peopleStorage)
    case .settings:
      SettingsView()
    case .recentlyDeleted:
      ReceiptTrashView()
    }
  }

  private func presentScanner() {
    recognitions.prewarm()
    isScannerPresented = true
  }

  /// Reading starts as soon as the scan exists, unless the model is unavailable. The receipt is
  /// pushed under the scanner, so closing the scanner reveals it without a second transition.
  private func capture(_ scan: ReceiptScan) {
    let input = ReceiptFlowInput.scan(scan, recognitions: recognitions)
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      path.append(.receipt(input))
    }
    isScannerPresented = false
  }
}

#Preview {
  HomeView()
    .environment(ReceiptLibraryModel(storage: .live))
    .environment(ReceiptRecognitionCenter(parsingClient: .standard, storage: .live))
}
