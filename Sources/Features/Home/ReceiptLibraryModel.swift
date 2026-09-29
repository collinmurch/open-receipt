import Observation
import SwiftUI

@MainActor
@Observable
final class ReceiptLibraryModel {
  private(set) var receipts: [ReceiptSummary] = [] {
    didSet { sections = ReceiptLibrarySections.grouped(receipts) }
  }
  /// `receipts` grouped by month, regrouped only when `receipts` changes.
  private(set) var sections: [ReceiptLibrarySection] = []
  private(set) var deletedReceipts: [DeletedReceiptSummary] = []
  private(set) var hasLoaded = false
  var errorDescription: String?

  private let storage: ReceiptStorageClient
  private var lastTrashPurgeCheck: Date?

  init(storage: ReceiptStorageClient) {
    self.storage = storage
  }

  func load() async {
    var purgeError: Error?
    do {
      try await purgeExpiredTrashIfNeeded(now: Date())
    } catch {
      purgeError = error
    }
    do {
      async let storedReceipts = storage.list()
      async let storedDeletedReceipts = storage.listDeleted()
      let receipts = try await storedReceipts
      let deletedReceipts = try await storedDeletedReceipts
      if receipts != self.receipts { self.receipts = receipts }
      if deletedReceipts != self.deletedReceipts { self.deletedReceipts = deletedReceipts }
      errorDescription = purgeError?.localizedDescription
    } catch {
      errorDescription = error.localizedDescription
    }
    if !hasLoaded { hasLoaded = true }
  }

  /// Moves `receipt` to Recently Deleted. A receipt deleted while it was first being read may not
  /// be listed yet, so the library reloads once it is gone.
  func delete(_ receipt: ReceiptSummary) async {
    guard let index = receipts.firstIndex(where: { $0.id == receipt.id }) else {
      do {
        try await storage.delete(receipt.id)
      } catch {
        errorDescription = error.localizedDescription
        return
      }
      await load()
      return
    }
    guard await remove(at: index, from: \.receipts, while: { try await storage.delete(receipt.id) })
    else { return }
    await reloadDeletedReceipts()
  }

  func restore(_ deletedReceipt: DeletedReceiptSummary) async {
    guard let index = deletedReceipts.firstIndex(where: { $0.id == deletedReceipt.id }) else {
      return
    }
    await remove(at: index, from: \.deletedReceipts) {
      try await storage.restore(deletedReceipt.id)
      receipts = try await storage.list()
    }
  }

  func permanentlyDelete(_ deletedReceipt: DeletedReceiptSummary) async {
    guard let index = deletedReceipts.firstIndex(where: { $0.id == deletedReceipt.id }) else {
      return
    }
    await remove(at: index, from: \.deletedReceipts) {
      try await storage.permanentlyDelete(deletedReceipt.id)
    }
  }

  func emptyTrash() async {
    let previousReceipts = deletedReceipts
    withAnimation(.smooth(duration: 0.4)) {
      deletedReceipts = []
    }

    do {
      try await storage.emptyTrash()
      errorDescription = nil
    } catch {
      let remainingReceipts = (try? await storage.listDeleted()) ?? previousReceipts
      withAnimation(.smooth(duration: 0.3)) {
        deletedReceipts = remainingReceipts
      }
      errorDescription = error.localizedDescription
    }
  }

  func refreshTrashIfNeeded(now: Date = Date()) async {
    do {
      guard try await purgeExpiredTrashIfNeeded(now: now) else { return }
      deletedReceipts = try await storage.listDeleted()
      errorDescription = nil
    } catch {
      errorDescription = error.localizedDescription
    }
  }

  @discardableResult
  private func purgeExpiredTrashIfNeeded(now: Date) async throws -> Bool {
    if let lastTrashPurgeCheck,
      now.timeIntervalSince(lastTrashPurgeCheck) < Self.trashPurgeCheckInterval
    {
      return false
    }
    lastTrashPurgeCheck = now
    try await storage.purgeExpiredTrash(now)
    return true
  }

  /// Removes the element at `index` right away, then puts it back if `operation` fails.
  @discardableResult
  private func remove<Element>(
    at index: Int,
    from list: ReferenceWritableKeyPath<ReceiptLibraryModel, [Element]>,
    while operation: () async throws -> Void
  ) async -> Bool {
    let element = withAnimation(.smooth(duration: 0.4)) {
      self[keyPath: list].remove(at: index)
    }
    do {
      try await operation()
      errorDescription = nil
      return true
    } catch {
      withAnimation(.smooth(duration: 0.3)) {
        self[keyPath: list].insert(element, at: min(index, self[keyPath: list].endIndex))
      }
      errorDescription = error.localizedDescription
      return false
    }
  }

  private func reloadDeletedReceipts() async {
    do {
      deletedReceipts = try await storage.listDeleted()
      errorDescription = nil
    } catch {
      errorDescription = error.localizedDescription
    }
  }

  private static let trashPurgeCheckInterval: TimeInterval = 24 * 60 * 60
}

/// Reloads the receipt library, for screens that change receipts while it is out of view.
struct ReceiptLibraryRefreshAction: Sendable {
  private let action: @MainActor @Sendable () -> Void

  init(action: @escaping @MainActor @Sendable () -> Void = {}) {
    self.action = action
  }

  init(library: ReceiptLibraryModel) {
    action = { Task { await library.load() } }
  }

  @MainActor
  func callAsFunction() {
    action()
  }
}

extension EnvironmentValues {
  @Entry var receiptLibraryRefresh = ReceiptLibraryRefreshAction()
}
