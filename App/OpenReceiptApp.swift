import SwiftUI

@main
struct OpenReceiptApp: App {
  @State private var library = ReceiptLibraryModel(storage: .live)
  @State private var recognitions = ReceiptRecognitionCenter(
    parsingClient: .standard,
    storage: .live,
    owner: { try? await PeopleStorageClient.live.owner() })

  var body: some Scene {
    WindowGroup {
      HomeView()
        .environment(library)
        .environment(recognitions)
    }
  }
}
