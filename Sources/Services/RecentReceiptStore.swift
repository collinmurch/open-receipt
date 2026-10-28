import Foundation

/// The receipts opened from the library most recently, newest first.
nonisolated struct RecentReceiptStore: Sendable {
  let load: @Sendable () -> [UUID]
  let save: @Sendable ([UUID]) -> Void
}

nonisolated extension RecentReceiptStore {
  static let live = RecentReceiptStore(
    load: {
      let ids = UserDefaults.standard.stringArray(forKey: RecentReceiptStore.key) ?? []
      return ids.compactMap(UUID.init(uuidString:))
    },
    save: { ids in
      UserDefaults.standard.set(ids.map(\.uuidString), forKey: RecentReceiptStore.key)
    })

  /// Keeps the receipts in memory, for tests and screenshots.
  static func memory(_ initial: [UUID] = []) -> RecentReceiptStore {
    let ids = Locked(initial)
    return RecentReceiptStore(load: { ids.value }, save: { ids.value = $0 })
  }

  private static let key = "recentlyOpenedReceipts"
}
