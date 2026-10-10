import SwiftUI

@main
struct OpenReceiptApp: App {
  @State private var library = ReceiptLibraryModel(storage: .live)
  @State private var access: ReadingAccess
  @State private var recognitions: ReceiptRecognitionCenter
  @State private var photos = ContactPhotos(client: .live)

  init() {
    let access = ReadingAccess(client: .standard, store: .live)
    _access = State(initialValue: access)
    _recognitions = State(
      initialValue: ReceiptRecognitionCenter(
        parsingClient: .standard,
        storage: .live,
        access: access,
        owner: { try? await PeopleStorageClient.live.owner() }))
  }

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
      .environment(access)
      .environment(photos)
      .task { await access.start() }
  }
}
