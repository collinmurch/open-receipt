import Foundation
import SwiftUI

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

extension EnvironmentValues {
  @Entry var receiptStorageClient = ReceiptStorageClient.live
}
