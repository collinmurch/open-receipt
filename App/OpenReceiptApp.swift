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
      #if DEBUG
        if let scenario = ScreenshotScenario.launched {
          ScreenshotScenarioView(scenario: scenario)
        } else {
          home
        }
      #else
        home
      #endif
    }
  }

  private var home: some View {
    HomeView()
      .environment(library)
      .environment(recognitions)
  }
}
