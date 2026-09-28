import SwiftUI

struct HomeView: View {
  @State private var isHistoryPresented = true
  @State private var navigationReceiptInput: ReceiptFlowInput?
  @State private var capturedReceiptInput: ReceiptFlowInput?
  @State private var isScannerPresented = false
  @State private var isPeoplePresented = false
  @State private var isPeoplePending = false
  @State private var isSettingsPresented = false
  @State private var isSettingsPending = false
  @Environment(ReceiptLibraryModel.self) private var library
  @Environment(ReceiptRecognitionCenter.self) private var recognitions
  @Environment(\.receiptStorageClient) private var storage
  @Environment(\.peopleStorageClient) private var peopleStorage

  var body: some View {
    NavigationStack {
      ReceiptLibraryView(
        isHistoryPresented: $isHistoryPresented,
        onHistoryDismiss: openPendingDestination,
        onOpen: open
      )
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            isSettingsPending = true
            isHistoryPresented = false
          } label: {
            Label("Settings", systemImage: "gearshape")
              .labelStyle(.iconOnly)
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button {
            isPeoplePending = true
            isHistoryPresented = false
          } label: {
            Label("People", systemImage: "person.2")
              .labelStyle(.iconOnly)
          }
        }
      }
      .navigationDestination(isPresented: peopleNavigationBinding) {
        PeopleView(storage: peopleStorage, receiptStorage: storage)
      }
      .navigationDestination(isPresented: settingsNavigationBinding) {
        PaymentMethodSettingsView()
      }
      .navigationDestination(isPresented: receiptNavigationBinding) {
        if let input = navigationReceiptInput {
          ReceiptFlowView(input: input)
        }
      }
    }
    .fullScreenCover(isPresented: $isScannerPresented, onDismiss: finishScannerDismissal) {
      ReceiptScannerView(
        onCapture: capture,
        onCancel: { isScannerPresented = false }
      )
      .ignoresSafeArea()
    }
    .environment(\.receiptLibraryRefresh, ReceiptLibraryRefreshAction(library: library))
  }

  private var receiptNavigationBinding: Binding<Bool> {
    Binding(
      get: { navigationReceiptInput != nil },
      set: { isPresented in
        guard !isPresented else { return }
        navigationReceiptInput = nil
        isHistoryPresented = true
      })
  }

  private func open(_ destination: ReceiptLibraryDestination) {
    switch destination {
    case .scanner:
      isScannerPresented = true
    case .receipt(let input):
      navigationReceiptInput = input
    }
  }

  /// Reading starts as soon as the scan exists; the receipt opens once the scanner has closed.
  private func capture(_ scan: ReceiptScan) {
    capturedReceiptInput = .recognition(recognitions.recognize(scan))
    isScannerPresented = false
  }

  private func finishScannerDismissal() {
    if let input = capturedReceiptInput {
      capturedReceiptInput = nil
      navigationReceiptInput = input
    } else {
      isHistoryPresented = true
    }
  }

  private var peopleNavigationBinding: Binding<Bool> {
    Binding(
      get: { isPeoplePresented },
      set: { isPresented in
        isPeoplePresented = isPresented
        if !isPresented {
          isHistoryPresented = true
        }
      })
  }

  private var settingsNavigationBinding: Binding<Bool> {
    Binding(
      get: { isSettingsPresented },
      set: { isPresented in
        isSettingsPresented = isPresented
        if !isPresented {
          isHistoryPresented = true
        }
      })
  }

  private func openPendingDestination() {
    if isSettingsPending {
      isSettingsPending = false
      isSettingsPresented = true
    } else if isPeoplePending {
      isPeoplePending = false
      isPeoplePresented = true
    }
  }
}

#Preview {
  HomeView()
    .environment(ReceiptLibraryModel(storage: .live))
    .environment(ReceiptRecognitionCenter(parsingClient: .standard, storage: .live))
}
