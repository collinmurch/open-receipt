import Foundation
import Synchronization
import XCTest

@testable import open_receipt

enum TestError: Error {
  case failed
  case unused
  case deleteFailed
  case restoreFailed
}

extension XCTestCase {
  /// A defaults suite only this test reads and writes, removed when the test ends.
  func isolatedDefaults() -> UserDefaults {
    let suiteName = "\(type(of: self))-\(UUID().uuidString)"
    addTeardownBlock {
      UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
    return UserDefaults(suiteName: suiteName)!
  }

  /// Reading access with no purchase that has already spent `used` free reads. Its testing settings
  /// are this test's own, so a purchase removed in the simulator's app can't unlock it.
  @MainActor
  func lockedAccess(used: Int = 0) -> ReadingAccess {
    let reads = used > 0 ? Set((1...used).map { "used-\($0)" }) : []
    return ReadingAccess(
      client: .fixed(isEntitled: false), store: .memory(reads), defaults: isolatedDefaults())
  }

  /// A directory only this test uses, removed when the test ends.
  func isolatedDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "\(type(of: self))-\(UUID().uuidString)", directoryHint: .isDirectory)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}

extension ParsedReceipt {
  /// A cafe receipt with `items`, by description and line total. The subtotal defaults to what the
  /// items come to, and zero leaves it off the receipt. The total defaults to what the subtotal, or
  /// the items without one, come to with the adjustments.
  static func fixture(
    items: KeyValuePairs<String, Money> = ["Coffee": 10, "Breakfast": 20],
    subtotal: Money? = nil,
    tax: Money = 0,
    tip: Money = 0,
    savings: Money = 0,
    total: Money? = nil,
    currency: String = "USD"
  ) -> ParsedReceipt {
    let itemsTotal = items.reduce(Money.zero) { $0 + $1.value }
    let subtotal = subtotal ?? itemsTotal
    return ParsedReceipt(
      merchantName: "Cafe",
      date: "2026-08-11",
      subtotal: subtotal,
      tax: tax,
      tip: tip,
      savings: savings,
      total: total
        ?? (subtotal > 0 ? subtotal : itemsTotal) + tax + tip - savings,
      currency: currency,
      items: items.map { ReceiptItem(description: $0.key, quantity: 1, lineTotal: $0.value) })
  }
}

extension ReceiptDraft {
  /// A draft of `ParsedReceipt.fixture` that lists the adjustments in `order`.
  static func fixture(
    items: KeyValuePairs<String, Money> = ["Coffee": 10, "Breakfast": 20],
    subtotal: Money? = nil,
    tax: Money = 0,
    tip: Money = 0,
    savings: Money = 0,
    total: Money? = nil,
    currency: String = "USD",
    order: [ReceiptTotalAdjustment] = [.tip, .tax, .savings],
    id: UUID = UUID()
  ) -> ReceiptDraft {
    ReceiptDraft(
      receipt: .fixture(
        items: items, subtotal: subtotal, tax: tax, tip: tip, savings: savings, total: total,
        currency: currency),
      id: id,
      backgroundStyle: .mint,
      adjustmentOrder: order)
  }

  /// The person using the app, who every draft starts with.
  var ownerID: ReceiptParticipant.ID {
    currentUser!.id
  }

  /// Adds a person who isn’t linked to a contact.
  @discardableResult
  func addManualParticipant(named name: String) -> ReceiptParticipant {
    addPerson(.fixture(name: name))
  }
}

extension Person {
  static func fixture(
    id: UUID = UUID(),
    name: String,
    contactIdentifier: String? = nil
  ) -> Person {
    let date = Date(timeIntervalSince1970: 1)
    return Person(
      id: id,
      createdAt: date,
      updatedAt: date,
      lastIncludedAt: date,
      displayName: name,
      contactIdentifier: contactIdentifier,
      paymentMethods: .init())
  }
}

extension ContactClient {
  /// Contacts that start at `status`, change to `requestedStatus` when access is requested, and
  /// hold `contacts` without photos.
  static func stub(
    status: ContactAuthorization = .authorized,
    requestedStatus: ContactAuthorization? = nil,
    contacts: [ContactSummary] = []
  ) -> ContactClient {
    ContactClient(
      authorizationStatus: { status },
      requestAccess: { requestedStatus ?? status },
      fetchContacts: { identifiers in
        guard let identifiers else { return contacts }
        return contacts.filter { identifiers.contains($0.identifier) }
      },
      fetchAvatar: { _ in nil })
  }
}

extension ReceiptBackgroundStyle {
  static let mint = ReceiptBackgroundStyle(primary: .mint, secondary: .blue)
  static let peach = ReceiptBackgroundStyle(primary: .peach, secondary: .rose)
}

extension ReceiptDocument {
  /// A stored receipt that hasn't been read yet.
  static func pending(
    id: UUID = UUID(),
    style: ReceiptBackgroundStyle = .mint,
    capturedAt: Date = Date(timeIntervalSince1970: 1),
    source: ReceiptScan.Source = .documentCamera
  ) -> ReceiptDocument {
    ReceiptDocument(
      schemaVersion: ReceiptDocument.currentSchemaVersion,
      id: id,
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1),
      presentation: .init(backgroundStyle: style),
      scan: .init(capturedAt: capturedAt, source: source, pages: []),
      recognition: .init(status: .pending, contractVersion: 1),
      receipt: nil,
      split: nil)
  }

  /// A stored, unread receipt for `scan`.
  static func pending(for scan: ReceiptScan, style: ReceiptBackgroundStyle = .mint)
    -> ReceiptDocument
  {
    .pending(id: scan.id, style: style, capturedAt: scan.capturedAt, source: scan.source)
  }
}

extension ReceiptSummary {
  /// A read cafe receipt in the library.
  static func fixture(
    id: UUID = UUID(),
    status: ReceiptDocument.Recognition.Status = .succeeded,
    localDate: String? = "2026-08-11",
    capturedAt: Date = Date(timeIntervalSince1970: 1),
    isUnavailable: Bool = false,
    personIDs: Set<UUID> = []
  ) -> ReceiptSummary {
    ReceiptSummary(
      id: id,
      updatedAt: capturedAt,
      capturedAt: capturedAt,
      backgroundStyle: .mint,
      recognitionStatus: status,
      merchantName: "Cafe",
      localDate: localDate,
      total: 11,
      currency: "USD",
      isUnavailable: isUnavailable,
      unavailableDescription: nil,
      personIDs: personIDs)
  }
}

extension ReceiptStorageClient {
  /// A client whose receipt operations throw `TestError.unused`. Trash operations keep their
  /// no-op defaults. Tests replace the operations they use.
  static let unimplemented = ReceiptStorageClient(
    create: { _, _ in throw TestError.unused },
    createBlank: { _, _ in throw TestError.unused },
    list: { throw TestError.unused },
    load: { _ in throw TestError.unused },
    loadPages: { _ in throw TestError.unused },
    pageURLs: { _ in throw TestError.unused },
    addPages: { _, _ in throw TestError.unused },
    deletePage: { _, _ in throw TestError.unused },
    reorderPages: { _, _ in throw TestError.unused },
    save: { _ in throw TestError.unused },
    delete: { _ in throw TestError.unused })
}

extension ReceiptStorageClient {
  /// A client for reading new scans: it stores each as an unread receipt with no pages, and hands
  /// what's saved to `recorder`.
  static func recognizing(recorder: Recorder<ReceiptDocument>? = nil) -> ReceiptStorageClient {
    var storage = ReceiptStorageClient.unimplemented
    storage.create = { scan, style in .pending(id: scan.id, style: style) }
    storage.list = { [] }
    storage.loadPages = { _ in [] }
    storage.pageURLs = { _ in [] }
    storage.save = { await recorder?.append($0) }
    storage.delete = { _ in }
    return storage
  }
}

extension ReceiptParsingClient {
  /// A client that reads every scan as `receipt`.
  static func reading(_ receipt: ParsedReceipt) -> ReceiptParsingClient {
    ReceiptParsingClient { _ in receipt }
  }
}

extension ReceiptRecognitionCenter {
  /// A center that reads the sample receipt at once and retries a lost connection without
  /// waiting.
  static func testing(
    parsingClient: ReceiptParsingClient = .sample(pacing: .zero),
    storage: ReceiptStorageClient = .recognizing(),
    access: ReadingAccess = .unlimited(),
    owner: ReceiptOwner? = nil,
    connectivity: ReceiptConnectivity = .immediate
  ) -> ReceiptRecognitionCenter {
    ReceiptRecognitionCenter(
      parsingClient: parsingClient,
      storage: storage,
      access: access,
      owner: { owner },
      connectivity: connectivity,
      connectionRetryDelay: .zero)
  }
}

extension ReceiptConnectivity {
  /// A connection that never returns until the waiting task is cancelled.
  static let offline = ReceiptConnectivity { try? await Task.sleep(for: .seconds(3600)) }
}

/// Values handed over from concurrent code, in the order they arrived.
actor Recorder<Value: Sendable> {
  private(set) var values: [Value] = []

  func append(_ value: Value) {
    values.append(value)
  }
}

/// Counts calls from synchronous or concurrent code.
final class CallCounter: Sendable {
  private let count = Mutex(0)

  var value: Int { count.withLock { $0 } }

  func increment() {
    count.withLock { $0 += 1 }
  }
}
