import Foundation
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
}

extension ReceiptDraft {
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

extension ReceiptConnectivity {
  /// A connection that never returns until the waiting task is cancelled.
  static let offline = ReceiptConnectivity { try? await Task.sleep(for: .seconds(3600)) }
}

extension ReadingAccess {
  /// Access with no purchase that has already spent `used` free reads. It keeps its testing
  /// settings in a fresh suite, so a purchase removed in the simulator's app can't lock it.
  static func locked(used: Int = 0) -> ReadingAccess {
    let reads = used > 0 ? Set((1...used).map { "used-\($0)" }) : []
    return ReadingAccess(
      client: .fixed(isEntitled: false),
      store: .memory(reads),
      defaults: UserDefaults(suiteName: "ReadingAccess.locked-\(UUID().uuidString)")!)
  }
}

actor SaveRecorder {
  private(set) var documents: [ReceiptDocument] = []

  func append(_ document: ReceiptDocument) {
    documents.append(document)
  }
}

actor CallCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}
