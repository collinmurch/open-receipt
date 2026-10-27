#if DEBUG
  import SwiftUI

  /// A fixed app state that `make previews` and `make screenshot` launch into. The capture tests
  /// pass `-ScreenshotScenario <kind>` and `-ScreenshotReceipt <path to scene JSON>`.
  struct ScreenshotScenario {
    enum Kind: String {
      /// A receipt partway through being read.
      case reading
      /// A read receipt with people assigned to its items.
      case split
      /// A completed split, open to its payment requests.
      case requests
      /// A completed split, sharing everyone's breakdowns with the group.
      case share
      /// A completed split whose breakdown slips are written as images for the App Store header.
      case breakdowns
      /// The receipt library with a few months of receipts.
      case library
      /// The unlimited reading purchase over the library, after the free reads are used. It is
      /// uploaded for App Review rather than shown on the App Store.
      case paywall
      /// A read receipt's items, before anyone is added to it.
      case review
      /// The review scenario's receipt being edited, from the top.
      case reviewEditing
      /// The review scenario's receipt being edited, typing its subtotal.
      case reviewKeyboard
      /// A read receipt asking about its tip, as it does right after reading.
      case tip
      /// A short read receipt that missed an item, so its items are short of the subtotal.
      case unbalanced
      /// A short read receipt being edited, whose misread tax leaves its total off.
      case unbalancedEditing
      /// The saved people, after splitting the requests scenario's receipt with them.
      case people
      /// Settings.
      case settings
      /// Recently Deleted, holding a few receipts from the library.
      case recentlyDeleted
    }

    let kind: Kind
    let scene: ScreenshotScene
    /// How many rows the reading screen shows. The last one is still being written.
    let readingRowCount: Int
    /// Where the breakdowns scenario writes its slips.
    let breakdownsDirectory: URL?

    static let launched: ScreenshotScenario? = {
      let defaults = UserDefaults.standard
      guard let rawKind = defaults.string(forKey: "ScreenshotScenario") else { return nil }
      guard let kind = Kind(rawValue: rawKind),
        let path = defaults.string(forKey: "ScreenshotReceipt")
      else { preconditionFailure("Unknown screenshot scenario \(rawKind).") }
      do {
        var scene = try ScreenshotScene.load(from: URL(filePath: path))
        if let style = defaults.string(forKey: "ScreenshotBackgroundStyle") {
          scene.backgroundStyle = try ReceiptBackgroundStyle(screenshotArgument: style)
        }
        let rows = defaults.integer(forKey: "ScreenshotReadingRows")
        return ScreenshotScenario(
          kind: kind,
          scene: scene,
          readingRowCount: rows > 0 ? rows : 8,
          breakdownsDirectory: defaults.string(forKey: "ScreenshotBreakdowns").map {
            URL(filePath: $0, directoryHint: .isDirectory)
          })
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
        recognitions: ReceiptRecognitionCenter = recognitions,
        access: ReadingAccess = .unlimited()
      ) -> ScreenshotStage {
        ScreenshotStage(
          path: path,
          library: ReceiptLibraryModel(storage: storage),
          storage: storage,
          people: people,
          parsing: parsing,
          recognitions: recognitions,
          access: access,
          contacts: kind == .share ? .cards(for: scene.people) : .unavailable,
          showsUnlimitedReading: kind == .paywall,
          receiptStartsAtTotals: [.unbalanced, .unbalancedEditing, .reviewKeyboard].contains(kind),
          receiptStartingField: kind == .reviewKeyboard ? .amount(.subtotal) : nil)
      }

      switch kind {
      case .reading:
        let reading = readingClient
        let readingCenter = ReceiptRecognitionCenter(parsingClient: reading, storage: storage)
        let recognition = readingCenter.recognize(
          scan, backgroundStyle: scene.backgroundStyle, isUserInitiated: false)
        return stage(
          [.receipt(.recognition(recognition))], parsing: reading, recognitions: readingCenter)

      case .breakdowns:
        let document = try await storeSplit(
          scan, storage: storage, people: people, completes: true)
        try writeBreakdowns(of: document)
        return stage([
          .receipt(
            .storedReceipt(document.id, backgroundStyle: scene.backgroundStyle, document: document))
        ])

      case .split, .requests, .share:
        let document = try await storeSplit(
          scan, storage: storage, people: people, completes: kind != .split)
        return stage([
          .receipt(
            .storedReceipt(document.id, backgroundStyle: scene.backgroundStyle, document: document))
        ])

      case .library:
        try await storeLibrary(scan, page: page, storage: storage)
        return stage([])

      case .paywall:
        try await storeLibrary(scan, page: page, storage: storage)
        let usedReads = (1...ReadingAccess.freeReadLimit).map { "screenshot-\($0)" }
        return stage(
          [],
          access: ReadingAccess(
            client: .fixed(isEntitled: false), store: .memory(Set(usedReads)), isUnlocked: false))

      case .review, .reviewEditing, .reviewKeyboard, .tip:
        var document = try await Self.storeRead(
          scene.receipt, scan: scan, backgroundStyle: scene.backgroundStyle, storage: storage)
        if kind != .tip {
          let draft = try ReceiptDraft(document: document)
          for adjustment in draft.unconfirmedAdjustments {
            draft.stopAsking(about: adjustment)
          }
          document = document.updating(from: draft)
          try await storage.save(document)
        }
        return stage([
          .receipt(
            .storedReceipt(
              document.id, backgroundStyle: scene.backgroundStyle, document: document,
              startsInEditing: kind == .reviewEditing || kind == .reviewKeyboard))
        ])

      case .unbalanced, .unbalancedEditing:
        let read = try await Self.storeRead(
          unbalancedReceipt, scan: scan, backgroundStyle: scene.backgroundStyle, storage: storage)
        let draft = try ReceiptDraft(document: read)
        for adjustment in draft.unconfirmedAdjustments {
          draft.stopAsking(about: adjustment)
        }
        let document = read.updating(from: draft)
        try await storage.save(document)
        return stage([
          .receipt(
            .storedReceipt(
              document.id, backgroundStyle: scene.backgroundStyle, document: document,
              startsInEditing: kind == .unbalancedEditing))
        ])

      case .people:
        _ = try await storeSplit(scan, storage: storage, people: people, completes: true)
        return stage([.people])

      case .settings:
        return stage([.settings])

      case .recentlyDeleted:
        try await storeLibrary(scan, page: page, storage: storage)
        for receipt in try await storage.list().prefix(3) {
          try await storage.delete(receipt.id)
        }
        return stage([.recentlyDeleted])
      }
    }

    /// The scene's first three items with the city's sales tax, read with a mistake: the
    /// unbalanced scenario misses the second item, and the editing one misreads the tax on a
    /// receipt with a printed tip.
    private var unbalancedReceipt: ParsedReceipt {
      var receipt = scene.receipt
      let items = Array(receipt.items.prefix(3))
      let subtotal = items.reduce(0) { $0 + $1.lineTotal }
      let tax = ReceiptCurrency.rounded(subtotal * 0.08875, code: receipt.currency)
      receipt.subtotal = subtotal
      if kind == .unbalanced {
        receipt.items = items.enumerated().filter { $0.offset != 1 }.map(\.element)
        receipt.tax = tax
        receipt.total = subtotal + tax
      } else {
        let tip = ReceiptCurrency.rounded(subtotal * 0.2, code: receipt.currency)
        receipt.items = items
        receipt.tax = tax - 0.45
        receipt.tip = tip
        receipt.total = subtotal + tax + tip
      }
      return receipt
    }

    /// Writes the overview slip and each person's slip as transparent PNGs, then
    /// `breakdowns.json` listing them in order, which tells the capture test they're done.
    @MainActor
    private func writeBreakdowns(of document: ReceiptDocument) throws {
      guard let directory = breakdownsDirectory else {
        throw ScreenshotSceneError.missingBreakdownsDirectory
      }
      guard
        let breakdowns = try ReceiptDraft(document: document).allBreakdowns(accentScheme: .light)
      else { throw ScreenshotSceneError.unassignedItems }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var names: [String] = []
      for breakdown in breakdowns {
        let name =
          switch breakdown.content {
          case .group: "overview.png"
          case .person(let share): "\(share.participant.displayName).png"
          }
        let renderer = ImageRenderer(
          content: ReceiptBreakdownSlip(breakdown: breakdown)
            .frame(width: Self.slipWidth)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large))
        renderer.proposedSize = ProposedViewSize(width: Self.slipWidth, height: nil)
        renderer.scale = 4
        guard let data = renderer.uiImage?.pngData() else {
          throw ScreenshotSceneError.unrenderedBreakdown(name)
        }
        try data.write(to: directory.appending(path: name))
        names.append(name)
      }
      try JSONEncoder().encode(names).write(to: directory.appending(path: "breakdowns.json"))
    }

    /// The slip's width inside a shared card.
    @MainActor private static let slipWidth = ReceiptBreakdownRenderer.width - 44

    /// Reads the scene's receipt as today's, and its library entries on their own days.
    @MainActor
    private func storeLibrary(
      _ scan: ReceiptScan,
      page: ReceiptPage,
      storage: ReceiptStorageClient
    ) async throws {
      let now = Date()
      var today = scene.receipt
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
      // Sharing splits the same receipt as the requests screen, and the header's slips the same
      // as the split screen.
      let groupName =
        switch kind {
        case .share, .people: Kind.requests.rawValue
        case .breakdowns: Kind.split.rawValue
        default: kind.rawValue
        }
      guard let group = scene.groups[groupName] else {
        throw ScreenshotSceneError.missingGroup(groupName)
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
        let contactIdentifier = kind == .share ? participant.contactIdentifier : nil
        var person = try await people.include(
          nil, participant.name, contactIdentifier, scan.capturedAt)
        person.paymentMethods = participant.paymentMethods
        let id = draft.addPerson(try await people.save(person)).id
        participants[participant.name] = id
        if let requestedAt = group.lastRequested(participant.name) {
          draft.recordRequest(for: id, at: requestedAt)
        }
      }
      for item in draft.items {
        let ids = Set((group.assignments[item.description] ?? []).compactMap { participants[$0] })
        draft.toggleAssignment(of: ids, to: item.id)
      }
      if let tip = scene.addedTip {
        draft.tip = tip
      }
      for adjustment in draft.unconfirmedAdjustments {
        draft.stopAsking(about: adjustment)
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
    let access: ReadingAccess
    let contacts: ContactClient
    /// Whether the unlimited reading purchase opens over the screen.
    let showsUnlimitedReading: Bool
    /// Whether the receipt's list starts scrolled to its totals.
    let receiptStartsAtTotals: Bool
    /// The field a receipt that opens in editing starts typing in.
    let receiptStartingField: ReceiptEditField?
  }

  /// Stages a scenario, then shows the app over it.
  struct ScreenshotScenarioView: View {
    let scenario: ScreenshotScenario
    @State private var stage: ScreenshotStage?
    @State private var showsUnlimitedReading = false

    var body: some View {
      Group {
        if let stage {
          HomeView(initialPath: stage.path)
            .screenshotHighlight(ScreenshotHighlights.readyName)
            .unlimitedReadingSheet(isPresented: $showsUnlimitedReading)
            .environment(stage.library)
            .environment(stage.recognitions)
            .environment(stage.access)
            .environment(\.receiptStorageClient, stage.storage)
            .environment(\.peopleStorageClient, stage.people)
            .environment(\.receiptParsingClient, stage.parsing)
            .environment(\.contactClient, stage.contacts)
            .environment(\.receiptStartsAtTotals, stage.receiptStartsAtTotals)
            .environment(\.receiptStartingField, stage.receiptStartingField)
        } else {
          Color.clear
        }
      }
      .task {
        do {
          let stage = try await scenario.stage()
          self.stage = stage
          showsUnlimitedReading = stage.showsUnlimitedReading
        } catch {
          preconditionFailure("Couldn't stage the \(scenario.kind) screenshot: \(error)")
        }
      }
    }
  }

  extension ContactClient {
    /// A client without access, so screenshots never read or prompt for real contacts.
    fileprivate static let unavailable = ContactClient(
      authorizationStatus: { .denied },
      requestAccess: { .denied },
      fetchContacts: { _ in [] },
      fetchAvatar: { _ in nil })

    /// A client whose only contacts are the scene's people with phone numbers, so screenshots can
    /// message them without reading real contacts.
    fileprivate static func cards(for people: [ScreenshotScene.Participant]) -> ContactClient {
      let contacts = people.compactMap { person -> ContactSummary? in
        guard let identifier = person.contactIdentifier, let phone = person.phone else {
          return nil
        }
        return ContactSummary(
          identifier: identifier,
          displayName: person.name,
          phoneNumbers: [ContactSummary.Value(label: "mobile", value: phone)])
      }
      return ContactClient(
        authorizationStatus: { .authorized },
        requestAccess: { .authorized },
        fetchContacts: { identifiers in
          identifiers.map { ids in contacts.filter { ids.contains($0.identifier) } } ?? contacts
        },
        fetchAvatar: { _ in nil })
    }
  }
#endif
