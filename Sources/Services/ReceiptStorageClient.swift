import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ReceiptStorageClient: Sendable {
  var create: @Sendable (ReceiptScan, ReceiptBackgroundStyle) async throws -> ReceiptDocument
  var createBlank: @Sendable (UUID, ReceiptBackgroundStyle) async throws -> ReceiptDocument
  var list: @Sendable () async throws -> [ReceiptSummary]
  var load: @Sendable (UUID) async throws -> ReceiptDocument
  var loadPages: @Sendable (UUID) async throws -> [ReceiptPage]
  var pageURLs: @Sendable (UUID) async throws -> [URL]
  var addPages: @Sendable (UUID, [ReceiptPage]) async throws -> ReceiptDocument
  var deletePage: @Sendable (UUID, ReceiptDocument.Page.ID) async throws -> ReceiptDocument
  var reorderPages: @Sendable (UUID, [ReceiptDocument.Page.ID]) async throws -> ReceiptDocument
  var save: @Sendable (ReceiptDocument) async throws -> Void
  var delete: @Sendable (UUID) async throws -> Void
  var listPersonSnapshots: @Sendable () async throws -> [ReceiptPersonSnapshot] = { [] }
  var listDeleted: @Sendable () async throws -> [DeletedReceiptSummary] = { [] }
  var restore: @Sendable (UUID) async throws -> Void = { _ in }
  var permanentlyDelete: @Sendable (UUID) async throws -> Void = { _ in }
  var emptyTrash: @Sendable () async throws -> Void = {}
  var purgeExpiredTrash: @Sendable (Date) async throws -> Void = { _ in }

  static let live = ReceiptStorageClient.files(.live)

  /// A client that stores receipts in `storage`.
  static func files(_ storage: ReceiptFileStorage) -> ReceiptStorageClient {
    ReceiptStorageClient(
      create: { try await storage.create(scan: $0, backgroundStyle: $1) },
      createBlank: {
        try await storage.createBlank(
          id: $0, backgroundStyle: $1, currency: CurrencySettings.defaultCode())
      },
      list: { try await storage.list() },
      load: { try await storage.load(id: $0) },
      loadPages: { try await storage.loadPages(id: $0) },
      pageURLs: { try await storage.pageURLs(id: $0) },
      addPages: { try await storage.addPages($1, to: $0) },
      deletePage: { try await storage.deletePage($1, from: $0) },
      reorderPages: { try await storage.reorderPages($1, in: $0) },
      save: { try await storage.save($0) },
      delete: { try await storage.delete(id: $0) },
      listPersonSnapshots: { try await storage.listPersonSnapshots() },
      listDeleted: { try await storage.listDeleted() },
      restore: { try await storage.restore(id: $0) },
      permanentlyDelete: { try await storage.permanentlyDelete(id: $0) },
      emptyTrash: { try await storage.emptyTrash() },
      purgeExpiredTrash: { try await storage.purgeExpiredTrash(now: $0) })
  }
}

struct DeletedReceiptSummary: Equatable, Identifiable, Sendable {
  let receipt: ReceiptSummary
  let deletedAt: Date

  var id: ReceiptSummary.ID { receipt.id }
}

actor ReceiptFileStorage {
  static let live = ReceiptFileStorage()

  private let fileManager: FileManager
  private let rootOverride: URL?
  private var documentCache: [UUID: CachedDocument] = [:]
  private var index: ReceiptLibraryIndex?
  private var isIndexChanged = false

  init(fileManager: FileManager = .default, rootURL: URL? = nil) {
    self.fileManager = fileManager
    rootOverride = rootURL
  }

  func create(
    scan: ReceiptScan,
    backgroundStyle: ReceiptBackgroundStyle = .random()
  ) throws -> ReceiptDocument {
    guard !scan.pages.isEmpty else { throw ReceiptStorageError.emptyScan }
    let root = try receiptsRoot()
    let stagingRoot = root.appending(path: ".staging", directoryHint: .isDirectory)
    try createProtectedDirectory(stagingRoot)
    let stagingURL = stagingRoot.appending(path: scan.id.uuidString, directoryHint: .isDirectory)
    let receiptURL = root.appending(path: scan.id.uuidString, directoryHint: .isDirectory)
    guard !fileManager.fileExists(atPath: receiptURL.path) else {
      throw ReceiptStorageError.receiptAlreadyExists(scan.id)
    }

    do {
      try createProtectedDirectory(stagingURL)
      let descriptors = try writePages(scan.pages, in: stagingURL)

      let now = Date()
      let document = ReceiptDocument(
        schemaVersion: ReceiptDocument.currentSchemaVersion,
        id: scan.id,
        createdAt: now,
        updatedAt: now,
        presentation: .init(backgroundStyle: backgroundStyle),
        scan: .init(capturedAt: scan.capturedAt, source: scan.source, pages: descriptors),
        recognition: .init(
          status: .pending,
          contractVersion: ReceiptModelContract.version,
          lastAttemptedAt: nil,
          completedAt: nil,
          warnings: [],
          failureMessage: nil),
        receipt: nil,
        split: nil)
      try write(document, in: stagingURL)
      try fileManager.moveItem(at: stagingURL, to: receiptURL)
      try protect(receiptURL)
      return document
    } catch {
      try? fileManager.removeItem(at: stagingURL)
      throw error
    }
  }

  func createBlank(
    id: UUID,
    backgroundStyle: ReceiptBackgroundStyle = .random(),
    currency: String = CurrencySettings.initialDefaultCode
  ) throws -> ReceiptDocument {
    let root = try receiptsRoot()
    let stagingRoot = root.appending(path: ".staging", directoryHint: .isDirectory)
    try createProtectedDirectory(stagingRoot)
    let stagingURL = stagingRoot.appending(path: id.uuidString, directoryHint: .isDirectory)
    let receiptURL = root.appending(path: id.uuidString, directoryHint: .isDirectory)
    guard !fileManager.fileExists(atPath: receiptURL.path) else {
      throw ReceiptStorageError.receiptAlreadyExists(id)
    }

    do {
      try createProtectedDirectory(stagingURL)
      let now = Date()
      let participantID = UUID()
      let document = ReceiptDocument(
        schemaVersion: ReceiptDocument.currentSchemaVersion,
        id: id,
        createdAt: now,
        updatedAt: now,
        presentation: .init(backgroundStyle: backgroundStyle),
        scan: .init(capturedAt: now, source: .manual, pages: []),
        recognition: .init(
          status: .succeeded,
          contractVersion: ReceiptModelContract.version,
          lastAttemptedAt: nil,
          completedAt: now,
          warnings: [],
          failureMessage: nil),
        receipt: .init(
          merchant: .init(name: ""),
          transaction: .init(localDate: ""),
          currency: currency,
          items: [],
          amounts: .init(subtotal: .init(0), adjustments: [], total: .init(0)),
          payment: nil),
        split: .init(
          adjustmentMethod: .proportional,
          participants: [
            .init(
              id: participantID,
              displayName: "Me",
              source: .init(type: .currentUser, identifier: nil))
          ],
          itemAssignments: []))
      try write(document, in: stagingURL)
      try fileManager.moveItem(at: stagingURL, to: receiptURL)
      try protect(receiptURL)
      return document
    } catch {
      try? fileManager.removeItem(at: stagingURL)
      throw error
    }
  }

  func list() throws -> [ReceiptSummary] {
    try removeStagedReceipts()
    return try libraryEntries().map(\.summary)
      .sorted {
        if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
        if $0.capturedAt != $1.capturedAt { return $0.capturedAt > $1.capturedAt }
        return $0.id.uuidString > $1.id.uuidString
      }
  }

  func load(id: UUID) throws -> ReceiptDocument {
    let url = try receiptDirectory(id: id).appending(path: "receipt.json")
    let modifiedAt = modificationDate(of: url)
    if let modifiedAt, let cached = documentCache[id], cached.modifiedAt == modifiedAt {
      return cached.document
    }
    let document = try decodeDocument(id: id, at: url)
    if let modifiedAt {
      documentCache[id] = CachedDocument(modifiedAt: modifiedAt, document: document)
    }
    return document
  }

  private func load(id: UUID, from directory: URL) throws -> ReceiptDocument {
    try decodeDocument(id: id, at: directory.appending(path: "receipt.json"))
  }

  private func decodeDocument(id: UUID, at url: URL) throws -> ReceiptDocument {
    let data = try Data(contentsOf: url)
    let document = try Self.decoder.decode(ReceiptDocument.self, from: data)
    guard document.schemaVersion == ReceiptDocument.currentSchemaVersion else {
      throw ReceiptDocumentError.unsupportedSchemaVersion(document.schemaVersion)
    }
    guard document.id == id else { throw ReceiptStorageError.identifierMismatch }
    return document
  }

  func loadPages(id: UUID) throws -> [ReceiptPage] {
    let document = try load(id: id)
    return try pageURLs(document: document).enumerated().map { index, url in
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else { throw ReceiptStorageError.unreadablePage(url.lastPathComponent) }
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
      let rawOrientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
      let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
      return ReceiptPage(
        image: image,
        orientation: orientation,
        sourceURL: url,
        pageIndex: index)
    }
  }

  func pageURLs(id: UUID) throws -> [URL] {
    try pageURLs(document: load(id: id))
  }

  /// Saves receipt values. Scan pages are owned by `addPages` and `deletePage`, so a stale
  /// snapshot never restores or drops pages.
  func save(_ document: ReceiptDocument) throws {
    guard document.schemaVersion == ReceiptDocument.currentSchemaVersion else {
      throw ReceiptDocumentError.unsupportedSchemaVersion(document.schemaVersion)
    }
    let directory = try receiptDirectory(id: document.id)
    var document = document
    if let stored = try? load(id: document.id) {
      guard stored.updatedAt <= document.updatedAt else { return }
      document.scan = stored.scan
    }
    try write(document, in: directory)
  }

  func addPages(_ pages: [ReceiptPage], to id: UUID) throws -> ReceiptDocument {
    guard !pages.isEmpty else { throw ReceiptStorageError.emptyScan }
    var document = try load(id: id)
    let directory = try receiptDirectory(id: id)
    let added = try writePages(pages, in: directory)
    document.scan.pages += added
    document.updatedAt = max(Date(), document.updatedAt)
    do {
      try write(document, in: directory)
    } catch {
      for page in added {
        try? fileManager.removeItem(at: directory.appending(path: page.file))
      }
      throw error
    }
    return document
  }

  func deletePage(_ pageID: ReceiptDocument.Page.ID, from id: UUID) throws -> ReceiptDocument {
    var document = try load(id: id)
    guard let index = document.scan.pages.firstIndex(where: { $0.id == pageID }) else {
      return document
    }
    guard document.scan.pages.count > 1 else { throw ReceiptStorageError.lastPage }
    let directory = try receiptDirectory(id: id)
    let pageURL = try pageURL(for: document.scan.pages[index], in: directory)
    document.scan.pages.remove(at: index)
    document.updatedAt = max(Date(), document.updatedAt)
    try write(document, in: directory)
    try? fileManager.removeItem(at: pageURL)
    return document
  }

  func delete(id: UUID) throws {
    let directory = try receiptDirectory(id: id)
    guard fileManager.fileExists(atPath: directory.path) else { return }
    let trash = try trashRoot()
    let deletedDirectory = trash.appending(path: id.uuidString, directoryHint: .isDirectory)
    guard !fileManager.fileExists(atPath: deletedDirectory.path) else {
      throw ReceiptStorageError.receiptAlreadyDeleted(id)
    }

    do {
      try fileManager.moveItem(at: directory, to: deletedDirectory)
      forget(id)
      let deletedAt = Date()
      try fileManager.setAttributes(
        [.modificationDate: deletedAt],
        ofItemAtPath: deletedDirectory.path)
      try writeDeletionRecord(.init(deletedAt: deletedAt), in: deletedDirectory)
    } catch {
      if fileManager.fileExists(atPath: deletedDirectory.path),
        !fileManager.fileExists(atPath: directory.path)
      {
        try? fileManager.moveItem(at: deletedDirectory, to: directory)
      }
      throw error
    }
  }

  func listDeleted() throws -> [DeletedReceiptSummary] {
    let trash = try trashRoot()
    let contents = try fileManager.contentsOfDirectory(
      at: trash,
      includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
      options: [.skipsHiddenFiles])
    return contents.compactMap { url in
      guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
      let deletedAt = deletionDate(in: url)
      let receipt: ReceiptSummary
      do {
        receipt = try summary(for: load(id: id, from: url))
      } catch {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let date = values?.contentModificationDate ?? deletedAt
        receipt = ReceiptSummary(
          id: id,
          updatedAt: date,
          capturedAt: date,
          backgroundStyle: .blue,
          recognitionStatus: .failed,
          merchantName: nil,
          localDate: nil,
          total: nil,
          currency: nil,
          isUnavailable: true,
          unavailableDescription: error.localizedDescription)
      }
      return DeletedReceiptSummary(receipt: receipt, deletedAt: deletedAt)
    }
    .sorted {
      if $0.deletedAt != $1.deletedAt { return $0.deletedAt > $1.deletedAt }
      return $0.id.uuidString > $1.id.uuidString
    }
  }

  func restore(id: UUID) throws {
    let deletedDirectory = try deletedReceiptDirectory(id: id)
    guard fileManager.fileExists(atPath: deletedDirectory.path) else { return }
    let directory = try receiptDirectory(id: id)
    guard !fileManager.fileExists(atPath: directory.path) else {
      throw ReceiptStorageError.receiptAlreadyExists(id)
    }
    try fileManager.moveItem(at: deletedDirectory, to: directory)
    let recordURL = directory.appending(path: "deletion.json")
    if fileManager.fileExists(atPath: recordURL.path) {
      try? fileManager.removeItem(at: recordURL)
    }
  }

  func permanentlyDelete(id: UUID) throws {
    let directory = try deletedReceiptDirectory(id: id)
    guard fileManager.fileExists(atPath: directory.path) else { return }
    try fileManager.removeItem(at: directory)
  }

  func emptyTrash() throws {
    let trash = try trashRoot()
    let contents = try fileManager.contentsOfDirectory(
      at: trash,
      includingPropertiesForKeys: nil)
    for url in contents {
      try fileManager.removeItem(at: url)
    }
  }

  func purgeExpiredTrash(now: Date) throws {
    let expirationDate = now.addingTimeInterval(-Self.trashRetentionInterval)
    for deletedReceipt in try listDeleted() where deletedReceipt.deletedAt < expirationDate {
      try permanentlyDelete(id: deletedReceipt.id)
    }
  }

  func listPersonSnapshots() throws -> [ReceiptPersonSnapshot] {
    try libraryEntries().flatMap(\.people)
  }

  /// Summaries and people for every stored receipt. Entries come from the persisted index while
  /// a receipt's file is unchanged, so only new or edited receipts are decoded.
  private func libraryEntries() throws -> [ReceiptLibraryIndex.Entry] {
    let root = try receiptsRoot()
    let contents = try fileManager.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles])
    var index = loadIndex()
    var entries: [ReceiptLibraryIndex.Entry] = []
    var storedIDs = Set<UUID>()

    for url in contents {
      guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
      storedIDs.insert(id)
      let modifiedAt = modificationDate(of: url.appending(path: "receipt.json"))
      if let modifiedAt, let entry = index.entries[id], entry.modifiedAt == modifiedAt {
        entries.append(entry)
        continue
      }
      let entry = libraryEntry(id: id, in: url, modifiedAt: modifiedAt)
      if modifiedAt != nil {
        index.entries[id] = entry
        isIndexChanged = true
      }
      entries.append(entry)
    }

    for id in index.entries.keys where !storedIDs.contains(id) {
      index.entries[id] = nil
      isIndexChanged = true
    }
    self.index = index
    if isIndexChanged {
      try? saveIndex(index)
    }
    return entries
  }

  private func libraryEntry(id: UUID, in directory: URL, modifiedAt: Date?)
    -> ReceiptLibraryIndex.Entry
  {
    do {
      let document = try load(id: id)
      return ReceiptLibraryIndex.Entry(
        modifiedAt: modifiedAt ?? .distantPast,
        summary: try summary(for: document),
        people: personSnapshots(in: document))
    } catch {
      let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
      let date = values?.contentModificationDate ?? .distantPast
      return ReceiptLibraryIndex.Entry(
        modifiedAt: modifiedAt ?? .distantPast,
        summary: ReceiptSummary(
          id: id,
          updatedAt: date,
          capturedAt: date,
          backgroundStyle: .blue,
          recognitionStatus: .failed,
          merchantName: nil,
          localDate: nil,
          total: nil,
          currency: nil,
          isUnavailable: true,
          unavailableDescription: error.localizedDescription),
        people: [])
    }
  }

  private func personSnapshots(in document: ReceiptDocument) -> [ReceiptPersonSnapshot] {
    (document.split?.participants ?? []).compactMap { participant in
      guard participant.source.type != .currentUser else { return nil }
      return ReceiptPersonSnapshot(
        receiptID: document.id,
        participantID: participant.id,
        personID: participant.personID,
        displayName: participant.displayName,
        contactIdentifier: participant.source.type == .contact
          ? participant.source.identifier : nil,
        includedAt: document.updatedAt)
    }
  }

  private func removeStagedReceipts() throws {
    let stagingRoot = try receiptsRoot().appending(path: ".staging", directoryHint: .isDirectory)
    guard fileManager.fileExists(atPath: stagingRoot.path) else { return }
    let stagedItems = try fileManager.contentsOfDirectory(
      at: stagingRoot,
      includingPropertiesForKeys: nil)
    for item in stagedItems {
      try fileManager.removeItem(at: item)
    }
  }

  private func loadIndex() -> ReceiptLibraryIndex {
    if let index { return index }
    guard let url = try? indexURL(),
      let data = try? Data(contentsOf: url),
      let stored = try? Self.indexDecoder.decode(ReceiptLibraryIndex.self, from: data),
      stored.version == ReceiptLibraryIndex.currentVersion
    else { return ReceiptLibraryIndex() }
    return stored
  }

  private func saveIndex(_ index: ReceiptLibraryIndex) throws {
    let url = try indexURL()
    try Self.indexEncoder.encode(index).write(to: url, options: .atomic)
    try protect(url)
    isIndexChanged = false
  }

  private func indexURL() throws -> URL {
    try receiptsRoot().appending(path: ".index.json")
  }

  private func modificationDate(of url: URL) -> Date? {
    try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
  }

  /// Records a document just written to `url`, so later loads and listings skip decoding it.
  private func remember(_ document: ReceiptDocument, writtenTo url: URL) {
    guard let modifiedAt = modificationDate(of: url) else { return }
    documentCache[document.id] = CachedDocument(modifiedAt: modifiedAt, document: document)
    guard let receiptSummary = try? summary(for: document) else { return }
    var index = loadIndex()
    index.entries[document.id] = ReceiptLibraryIndex.Entry(
      modifiedAt: modifiedAt,
      summary: receiptSummary,
      people: personSnapshots(in: document))
    self.index = index
    isIndexChanged = true
  }

  private func forget(_ id: UUID) {
    documentCache[id] = nil
    var index = loadIndex()
    guard index.entries.removeValue(forKey: id) != nil else { return }
    self.index = index
    isIndexChanged = true
  }

  private func summary(for document: ReceiptDocument) throws -> ReceiptSummary {
    let total = try document.receipt.map { try decimal($0.amounts.total) }
    return ReceiptSummary(
      id: document.id,
      updatedAt: document.updatedAt,
      capturedAt: document.scan.capturedAt,
      backgroundStyle: document.presentation.backgroundStyle,
      recognitionStatus: document.recognition.status,
      merchantName: document.receipt?.merchant.name,
      localDate: document.receipt?.transaction.localDate,
      total: total,
      currency: document.receipt?.currency,
      isUnavailable: false,
      unavailableDescription: nil,
      deferredUntil: document.recognition.status == .succeeded
        ? nil : document.recognition.deferredUntil)
  }

  private func pageURLs(document: ReceiptDocument) throws -> [URL] {
    let directory = try receiptDirectory(id: document.id)
    return try document.scan.pages.map { page in
      let url = try pageURL(for: page, in: directory)
      guard fileManager.fileExists(atPath: url.path) else {
        throw ReceiptStorageError.unreadablePage(url.lastPathComponent)
      }
      return url
    }
  }

  private func pageURL(for page: ReceiptDocument.Page, in directory: URL) throws -> URL {
    guard page.file.hasPrefix("pages/"),
      !page.file.contains(".."),
      page.file.split(separator: "/").count == 2
    else { throw ReceiptDocumentError.invalidPagePath(page.file) }
    let url = directory.appending(path: page.file)
    let standardizedDirectory = directory.standardizedFileURL.path + "/"
    guard url.standardizedFileURL.path.hasPrefix(standardizedDirectory) else {
      throw ReceiptDocumentError.invalidPagePath(page.file)
    }
    return url
  }

  func reorderPages(_ pageIDs: [ReceiptDocument.Page.ID], in id: UUID) throws
    -> ReceiptDocument
  {
    var document = try load(id: id)
    let pagesByID = Dictionary(uniqueKeysWithValues: document.scan.pages.map { ($0.id, $0) })
    let reordered = pageIDs.compactMap { pagesByID[$0] }
    guard reordered.count == document.scan.pages.count, Set(pageIDs).count == pageIDs.count
    else { throw ReceiptStorageError.pagesChanged }
    guard reordered != document.scan.pages else { return document }
    document.scan.pages = reordered
    document.updatedAt = max(Date(), document.updatedAt)
    try write(document, in: try receiptDirectory(id: id))
    return document
  }

  private func writePages(_ pages: [ReceiptPage], in directory: URL) throws
    -> [ReceiptDocument.Page]
  {
    let pagesURL = directory.appending(path: "pages", directoryHint: .isDirectory)
    try createProtectedDirectory(pagesURL)
    var written: [ReceiptDocument.Page] = []
    do {
      for page in pages {
        let id = UUID()
        let filename = "\(id.uuidString.lowercased()).heic"
        let url = pagesURL.appending(path: filename)
        try Self.writeHEIC(page, to: url)
        try protect(url)
        written.append(
          ReceiptDocument.Page(id: id, file: "pages/\(filename)", mediaType: "image/heic"))
      }
    } catch {
      for page in written {
        try? fileManager.removeItem(at: directory.appending(path: page.file))
      }
      throw error
    }
    return written
  }

  private func receiptsRoot() throws -> URL {
    if let rootOverride {
      try createProtectedDirectory(rootOverride)
      return rootOverride
    }
    let applicationSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true)

    let root =
      applicationSupport
      .appending(path: "OpenReceipt", directoryHint: .isDirectory)
      .appending(path: "Receipts", directoryHint: .isDirectory)
    try createProtectedDirectory(root)
    return root
  }

  private func receiptDirectory(id: UUID) throws -> URL {
    try receiptsRoot().appending(path: id.uuidString, directoryHint: .isDirectory)
  }

  private func trashRoot() throws -> URL {
    let trash = try receiptsRoot().appending(path: ".trash", directoryHint: .isDirectory)
    try createProtectedDirectory(trash)
    return trash
  }

  private func deletedReceiptDirectory(id: UUID) throws -> URL {
    try trashRoot().appending(path: id.uuidString, directoryHint: .isDirectory)
  }

  private func writeDeletionRecord(_ record: DeletionRecord, in directory: URL) throws {
    let url = directory.appending(path: "deletion.json")
    let data = try Self.encoder.encode(record)
    try data.write(to: url, options: .atomic)
    try protect(url)
  }

  private func deletionDate(in directory: URL) -> Date {
    let recordURL = directory.appending(path: "deletion.json")
    if let data = try? Data(contentsOf: recordURL),
      let record = try? Self.decoder.decode(DeletionRecord.self, from: data)
    {
      return record.deletedAt
    }
    let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
    return values?.contentModificationDate ?? .distantPast
  }

  private func createProtectedDirectory(_ url: URL) throws {
    try fileManager.createDirectory(
      at: url,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
  }

  private func protect(_ url: URL) throws {
    try fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path)
  }

  private func write(_ document: ReceiptDocument, in directory: URL) throws {
    let data = try Self.encoder.encode(document)
    let url = directory.appending(path: "receipt.json")
    try data.write(to: url, options: .atomic)
    try protect(url)
    remember(document, writtenTo: url)
  }

  private func decimal(_ value: DecimalString) throws -> Double {
    guard let result = value.doubleValue else {
      throw ReceiptDocumentError.invalidDecimal(value.value)
    }
    return result
  }

  private static func writeHEIC(_ page: ReceiptPage, to url: URL) throws {
    guard let image = ReceiptImageNormalizer.normalized(page.image, orientation: page.orientation),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.heic.identifier as CFString,
        1,
        nil)
    else { throw ReceiptStorageError.cannotEncodePage }
    let properties = [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else {
      throw ReceiptStorageError.cannotEncodePage
    }
  }

  private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let wholeSecondTimestampStyle = Date.ISO8601FormatStyle()

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(date.formatted(ReceiptFileStorage.timestampStyle))
    }
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      if let date = try? ReceiptFileStorage.timestampStyle.parse(value) { return date }
      guard let date = try? ReceiptFileStorage.wholeSecondTimestampStyle.parse(value) else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Expected an ISO 8601 timestamp.")
      }
      return date
    }
    return decoder
  }()

  private static let indexEncoder = JSONEncoder()
  private static let indexDecoder = JSONDecoder()

  private static let trashRetentionInterval: TimeInterval = 30 * 24 * 60 * 60

  private struct CachedDocument {
    let modifiedAt: Date
    let document: ReceiptDocument
  }

  private struct DeletionRecord: Codable {
    let deletedAt: Date
  }
}

/// Summaries of stored receipts, keyed by the modification date of each receipt's file.
struct ReceiptLibraryIndex: Codable {
  static let currentVersion = 2

  struct Entry: Codable {
    let modifiedAt: Date
    let summary: ReceiptSummary
    let people: [ReceiptPersonSnapshot]
  }

  var version = currentVersion
  var entries: [UUID: Entry] = [:]
}

enum ReceiptStorageError: Error, LocalizedError {
  case emptyScan
  case receiptAlreadyExists(UUID)
  case receiptAlreadyDeleted(UUID)
  case identifierMismatch
  case cannotEncodePage
  case unreadablePage(String)
  case lastPage
  case pagesChanged

  var errorDescription: String? {
    switch self {
    case .emptyScan:
      "The scan does not contain any receipt pages."
    case .receiptAlreadyExists:
      "A receipt with this identifier already exists."
    case .receiptAlreadyDeleted:
      "This receipt is already in Recently Deleted."
    case .identifierMismatch:
      "The receipt identifier does not match its storage directory."
    case .cannotEncodePage:
      "A receipt page could not be encoded."
    case .unreadablePage(let name):
      "The receipt page \(name) could not be read."
    case .lastPage:
      "A scanned receipt needs at least one page."
    case .pagesChanged:
      "The receipt pages changed while they were being reordered. Try again."
    }
  }
}

private struct ReceiptStorageClientKey: EnvironmentKey {
  static let defaultValue = ReceiptStorageClient.live
}

extension EnvironmentValues {
  var receiptStorageClient: ReceiptStorageClient {
    get { self[ReceiptStorageClientKey.self] }
    set { self[ReceiptStorageClientKey.self] = newValue }
  }
}
