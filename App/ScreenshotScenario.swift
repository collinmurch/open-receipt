#if DEBUG
  import SwiftUI

  /// A fixed app state that `make screenshots` launches into. The capture tests pass
  /// `-ScreenshotScenario <kind>` and `-ScreenshotReceipt <path to scene JSON>`.
  struct ScreenshotScenario {
    enum Kind: String {
      /// A receipt partway through being read.
      case reading
      /// A read receipt with people assigned to its items.
      case split
      /// A completed split, open to its payment requests.
      case requests
      /// The receipt library with a few months of receipts.
      case library
    }

    let kind: Kind
    let scene: ScreenshotScene
    /// How many rows the reading screen shows. The last one is still being written.
    let readingRowCount: Int
    let colorScheme: ColorScheme

    static let launched: ScreenshotScenario? = {
      let defaults = UserDefaults.standard
      guard let rawKind = defaults.string(forKey: "ScreenshotScenario") else { return nil }
      guard let kind = Kind(rawValue: rawKind),
        let path = defaults.string(forKey: "ScreenshotReceipt")
      else { preconditionFailure("Unknown screenshot scenario \(rawKind).") }
      do {
        let scene = try ScreenshotScene.load(from: URL(filePath: path))
        let rows = defaults.integer(forKey: "ScreenshotReadingRows")
        return ScreenshotScenario(
          kind: kind,
          scene: scene,
          readingRowCount: rows > 0 ? rows : 8,
          colorScheme: defaults.string(forKey: "ScreenshotAppearance") == "dark" ? .dark : .light)
      } catch {
        preconditionFailure("Couldn't load the screenshot scene at \(path): \(error)")
      }
    }()

    @MainActor
    func stage() async throws -> ScreenshotStage {
      let root = URL.temporaryDirectory.appending(
        path: "Screenshots-\(UUID().uuidString)", directoryHint: .isDirectory)
      let storage = ReceiptStorageClient.files(
        ReceiptFileStorage(rootURL: root.appending(path: "Receipts", directoryHint: .isDirectory)))
      let people = PeopleStorageClient.files(
        PeopleFileStorage(rootURL: root.appending(path: "People", directoryHint: .isDirectory)))
      guard let page = ReceiptPhotoImporter.page(from: try Data(contentsOf: scene.imageURL))
      else { throw ScreenshotSceneError.unreadableImage(scene.imageURL) }
      let scan = ReceiptScan(id: scene.id, pages: [page], source: .photoLibrary)
      let receipt = scene.receipt
      let parsing = ReceiptParsingClient(usesSampleData: false) { _ in receipt }
      let recognitions = ReceiptRecognitionCenter(parsingClient: parsing, storage: storage)

      func stage(
        _ path: [HomeRoute],
        parsing: ReceiptParsingClient = parsing,
        recognitions: ReceiptRecognitionCenter = recognitions
      ) -> ScreenshotStage {
        ScreenshotStage(
          path: path,
          library: ReceiptLibraryModel(storage: storage),
          storage: storage,
          people: people,
          parsing: parsing,
          recognitions: recognitions)
      }

      switch kind {
      case .reading:
        let reading = readingClient
        let readingCenter = ReceiptRecognitionCenter(parsingClient: reading, storage: storage)
        let recognition = readingCenter.recognize(
          scan, backgroundStyle: scene.backgroundStyle, isUserInitiated: false)
        return stage(
          [.receipt(.recognition(recognition))], parsing: reading, recognitions: readingCenter)

      case .split, .requests:
        let document = try await storeSplit(
          scan, storage: storage, people: people, completes: kind == .requests)
        return stage([
          .receipt(
            .storedReceipt(document.id, backgroundStyle: scene.backgroundStyle, document: document))
        ])

      case .library:
        let now = Date()
        var today = receipt
        today.date = Self.localDate(daysBefore: 0, now: now)
        _ = try await Self.storeRead(
          today, scan: scan, backgroundStyle: scene.backgroundStyle, storage: storage)
        for entry in scene.library ?? [] {
          let captured = ReceiptScan(
            pages: [page],
            capturedAt: now.addingTimeInterval(-Double(entry.daysAgo) * 24 * 60 * 60),
            source: .documentCamera)
          _ = try await Self.storeRead(
            entry.receipt(date: Self.localDate(daysBefore: entry.daysAgo, now: now)),
            scan: captured,
            backgroundStyle: entry.backgroundStyle,
            storage: storage)
        }
        return stage([])
      }
    }

    /// Streams the first `readingRowCount` rows, leaves the last one half written, and then waits
    /// so the screen holds still.
    private var readingClient: ReceiptParsingClient {
      let receipt = scene.receipt
      let rowCount = readingRowCount
      return ReceiptParsingClient(usesSampleData: false) { _, onPreview in
        var preview = ReceiptParsePreview(
          merchantName: receipt.merchantName,
          date: receipt.date,
          total: receipt.total,
          currency: receipt.currency)
        await onPreview(preview)
        for (index, item) in receipt.items.prefix(rowCount).enumerated() {
          try await Task.sleep(for: .milliseconds(60))
          if index == rowCount - 1 {
            let words = item.description.split(separator: " ")
            let written = words.prefix(max(1, words.count - 1)).joined(separator: " ")
            preview.items.append(ReceiptParsePreview.Item(description: written))
          } else {
            preview.items.append(
              ReceiptParsePreview.Item(
                description: item.description,
                quantity: item.quantity,
                lineTotal: item.lineTotal))
          }
          await onPreview(preview)
        }
        try await Task.sleep(for: .seconds(24 * 60 * 60))
        return receipt
      }
    }

    /// Reads the scene's receipt, then adds its people, assignments, and tip the way someone would
    /// after reading it.
    @MainActor
    private func storeSplit(
      _ scan: ReceiptScan,
      storage: ReceiptStorageClient,
      people: PeopleStorageClient,
      completes: Bool
    ) async throws -> ReceiptDocument {
      let document = try await Self.storeRead(
        scene.receipt, scan: scan, backgroundStyle: scene.backgroundStyle, storage: storage)
      guard let group = scene.groups[kind.rawValue] else {
        throw ScreenshotSceneError.missingGroup(kind.rawValue)
      }
      let draft = try ReceiptDraft(document: document)
      if let owner = group.owner {
        draft.setOwner(ReceiptOwner(contactIdentifier: "", displayName: owner))
      }
      var participants: [String: ReceiptParticipant.ID] = [:]
      if let currentUser = draft.currentUser {
        participants[currentUser.displayName] = currentUser.id
      }
      let names = Set(group.assignments.values.joined())
      for participant in scene.people where names.contains(participant.name) {
        var person = try await people.include(nil, participant.name, nil, scan.capturedAt)
        person.paymentMethods = participant.paymentMethods
        participants[participant.name] = draft.addPerson(try await people.save(person)).id
      }
      for item in draft.items {
        let ids = Set((group.assignments[item.description] ?? []).compactMap { participants[$0] })
        draft.toggleAssignment(of: ids, to: item.id)
      }
      if let tip = scene.addedTip {
        draft.tip = tip
        draft.fixTotal()
      }
      if completes {
        draft.complete()
      }
      let split = document.updating(from: draft)
      try await storage.save(split)
      return split
    }

    @MainActor
    private static func storeRead(
      _ receipt: ParsedReceipt,
      scan: ReceiptScan,
      backgroundStyle: ReceiptBackgroundStyle,
      storage: ReceiptStorageClient
    ) async throws -> ReceiptDocument {
      let center = ReceiptRecognitionCenter(
        parsingClient: ReceiptParsingClient(usesSampleData: false) { _ in receipt },
        storage: storage)
      let recognition = center.recognize(
        scan, backgroundStyle: backgroundStyle, isUserInitiated: false)
      guard case .recognized(let document) = await recognition.outcome else {
        throw ScreenshotSceneError.unreadReceipt
      }
      return document
    }

    private static func localDate(daysBefore days: Int, now: Date) -> String {
      let date = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
      return ReceiptLocalDate.string(from: date, in: .current)
    }
  }

  /// The storage, clients, and navigation a scenario starts with.
  struct ScreenshotStage {
    let path: [HomeRoute]
    let library: ReceiptLibraryModel
    let storage: ReceiptStorageClient
    let people: PeopleStorageClient
    let parsing: ReceiptParsingClient
    let recognitions: ReceiptRecognitionCenter
  }

  /// A receipt photo and the values it reads as, who had what, and the rest of the library.
  struct ScreenshotScene: Decodable {
    struct Item: Decodable {
      let description: String
      var quantity: Double?
      let lineTotal: Double
    }

    /// Who is on a scenario's receipt and which items each of them had. Names match `people`, and
    /// the person using the app is `owner`, or "Me" without one.
    struct Group: Decodable {
      var owner: String?
      let assignments: [String: [String]]
    }

    /// Someone on the receipt, with the payment method they are requested through.
    struct Participant: Decodable {
      let name: String
      var venmo: String?
      var cashApp: String?
      var iMessage: String?

      var paymentMethods: Person.PaymentMethods {
        let defaultMethod: PaymentMethod? =
          if venmo != nil { .venmo } else if cashApp != nil { .cashApp } else if iMessage != nil {
            .iMessage
          } else { nil }
        return Person.PaymentMethods(
          defaultMethod: defaultMethod,
          venmo: venmo.map(Person.Venmo.init(username:)),
          cashApp: cashApp.map { Person.CashApp(cashtag: $0) },
          iMessage: iMessage.map {
            Person.IMessage(recipient: .init(kind: .phoneNumber, value: $0))
          })
      }
    }

    /// Another receipt in the library, dated relative to the capture.
    struct LibraryEntry: Decodable {
      let merchant: String
      let daysAgo: Int
      let total: Double
      let backgroundStyle: ReceiptBackgroundStyle

      func receipt(date: String) -> ParsedReceipt {
        ParsedReceipt(
          merchantName: merchant,
          date: date,
          subtotal: total,
          total: total,
          items: [ReceiptItem(description: merchant, quantity: 1, lineTotal: total)])
      }
    }

    let id: UUID
    let image: String
    let merchant: String
    let date: String
    let currency: String
    let subtotal: Double
    let tax: Double
    let total: Double
    /// A tip entered after the receipt is read.
    var addedTip: Double?
    let backgroundStyle: ReceiptBackgroundStyle
    let people: [Participant]
    let items: [Item]
    /// People and assignments for each scenario that splits the receipt, keyed by scenario.
    let groups: [String: Group]
    var library: [LibraryEntry]?
    private(set) var imageURL = URL(filePath: "/")

    private enum CodingKeys: String, CodingKey {
      case id, image, merchant, date, currency, subtotal, tax, total, addedTip, backgroundStyle,
        people, items, groups, library
    }

    static func load(from url: URL) throws -> ScreenshotScene {
      var scene = try JSONDecoder().decode(ScreenshotScene.self, from: Data(contentsOf: url))
      scene.imageURL = url.deletingLastPathComponent().appending(path: scene.image)
      return scene
    }

    var receipt: ParsedReceipt {
      ParsedReceipt(
        merchantName: merchant,
        date: date,
        subtotal: subtotal,
        tax: tax,
        total: total,
        currency: currency,
        items: items.map {
          ReceiptItem(
            description: $0.description, quantity: $0.quantity ?? 1, lineTotal: $0.lineTotal)
        })
    }
  }

  extension ContactClient {
    /// A client without access, so screenshots never read or prompt for real contacts.
    fileprivate static let unavailable = ContactClient(
      authorizationStatus: { .denied },
      requestAccess: { .denied },
      fetchContacts: { _ in [] },
      fetchAvatar: { _ in nil })
  }

  enum ScreenshotSceneError: Error {
    case unreadableImage(URL)
    case unreadReceipt
    case missingGroup(String)
  }

  /// Stages a scenario, then shows the app over it.
  struct ScreenshotScenarioView: View {
    let scenario: ScreenshotScenario
    @State private var stage: ScreenshotStage?

    var body: some View {
      Group {
        if let stage {
          HomeView(initialPath: stage.path)
            .environment(stage.library)
            .environment(stage.recognitions)
            .environment(\.receiptStorageClient, stage.storage)
            .environment(\.peopleStorageClient, stage.people)
            .environment(\.receiptParsingClient, stage.parsing)
            .environment(\.contactClient, .unavailable)
        } else {
          Color.clear
        }
      }
      .preferredColorScheme(scenario.colorScheme)
      .task {
        do {
          stage = try await scenario.stage()
        } catch {
          preconditionFailure("Couldn't stage the \(scenario.kind) screenshot: \(error)")
        }
      }
    }
  }
#endif
