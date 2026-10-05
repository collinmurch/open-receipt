import Foundation
import Observation

/// Whether receipts can be read: unlimited after the one-time purchase, and a few free reads
/// before it. Each free read is recorded under a key when it starts, so a read that is retried,
/// deferred, or resumed later uses one free read in all.
@MainActor
@Observable
final class ReadingAccess {
  static let freeReadLimit = 5

  private(set) var isUnlocked: Bool
  /// The purchase's localized price, once it has loaded.
  private(set) var displayPrice: String?
  private(set) var channel = BuildChannel.current
  private var usedReads: Set<String>

  @ObservationIgnored private let client: PurchaseClient
  @ObservationIgnored private let store: FreeReadStore
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let resolveChannel: @Sendable () async -> BuildChannel

  init(
    client: PurchaseClient,
    store: FreeReadStore,
    isUnlocked: Bool = false,
    defaults: UserDefaults = .standard,
    resolveChannel: @escaping @Sendable () async -> BuildChannel = BuildChannel.resolve
  ) {
    self.client = client
    self.store = store
    self.isUnlocked = isUnlocked
    self.defaults = defaults
    self.resolveChannel = resolveChannel
    usedReads = store.load()
  }

  /// Reading without limits or the App Store, for tests and previews.
  static func unlimited() -> ReadingAccess {
    ReadingAccess(
      client: .fixed(isEntitled: true),
      store: .memory(),
      isUnlocked: true,
      resolveChannel: { .appStore })
  }

  var freeReadsLeft: Int {
    max(0, Self.freeReadLimit - usedReads.count)
  }

  /// "1 free read left", "5 free reads left", and so on.
  var freeReadsLeftDescription: String {
    String(inflecting: "^[\(freeReadsLeft) free read](inflect: true) left")
  }

  var hasUsedFreeReads: Bool {
    !usedReads.isEmpty
  }

  /// Whether the build tests purchases, where free reads can be reset and the purchase removed.
  var isTesting: Bool {
    channel.isTesting
  }

  /// Follows purchases and the free read record for as long as the calling task runs.
  func start() async {
    // The channel decides whether a purchase removed in testing counts, so it comes first.
    channel = await resolveChannel()
    await refresh()
    // Writing the whole record back restores any store that was cleared.
    if !usedReads.isEmpty { store.save(usedReads) }
    let updates = client.updates()
    let changes = store.changes()
    let purchases = Task {
      for await _ in updates { await refresh() }
    }
    let records = Task {
      for await _ in changes { mergeStoredReads() }
    }
    await withTaskCancellationHandler {
      await purchases.value
      await records.value
    } onCancel: {
      purchases.cancel()
      records.cancel()
    }
  }

  func refresh() async {
    let isEntitled = await client.isEntitled()
    isUnlocked = isEntitled && !(isTesting && isPurchaseRemovedForTesting)
    mergeStoredReads()
  }

  /// Lets a read recorded under `key` start. Without the purchase, a new key uses a free read,
  /// and none is left once they are all used.
  func admit(_ key: String) -> Bool {
    if isUnlocked || usedReads.contains(key) { return true }
    mergeStoredReads()
    guard usedReads.count < Self.freeReadLimit else { return false }
    usedReads.insert(key)
    store.save(usedReads)
    return true
  }

  /// Admits `key` after checking the purchase again, for a read refused before it was known.
  func admitAfterRefreshing(_ key: String) async -> Bool {
    await refresh()
    return admit(key)
  }

  /// Returns the free read recorded under `key`, for a read that ended without using it.
  func release(_ key: String) {
    guard usedReads.remove(key) != nil else { return }
    store.save(usedReads)
  }

  func loadPrice() async throws {
    displayPrice = try await client.displayPrice()
  }

  func purchase() async throws -> PurchaseOutcome {
    let outcome = try await client.purchase()
    if outcome == .purchased {
      isPurchaseRemovedForTesting = false
      await refresh()
    }
    return outcome
  }

  /// Asks the App Store for this account's purchase, and throws when there isn't one.
  func restore() async throws {
    try await client.restore()
    isPurchaseRemovedForTesting = false
    await refresh()
    if !isUnlocked { throw PurchaseError.nothingToRestore }
  }

  /// Sets how many free reads are left, keeping the reads already recorded where it can. Only
  /// builds that test purchases can.
  func setFreeReadsLeftForTesting(_ count: Int) {
    guard isTesting else { return }
    let used = Self.freeReadLimit - min(max(count, 0), Self.freeReadLimit)
    var reads = Set(usedReads.sorted().prefix(used))
    var filler = 0
    while reads.count < used {
      reads.insert("testing-\(filler)")
      filler += 1
    }
    usedReads = reads
    store.save(reads)
  }

  /// Treats this build as if the purchase was never made, until it is bought or restored again.
  /// The App Store keeps the purchase, so only builds that test purchases can.
  func removePurchaseForTesting() async {
    guard isTesting else { return }
    isPurchaseRemovedForTesting = true
    await refresh()
  }

  /// Ignored in the production App Store, so it can only hide a purchase made in testing.
  private var isPurchaseRemovedForTesting: Bool {
    get { defaults.bool(forKey: Self.removedPurchaseKey) }
    set { defaults.set(newValue, forKey: Self.removedPurchaseKey) }
  }

  private static let removedPurchaseKey = "TestingPurchaseRemoved"

  private func mergeStoredReads() {
    let stored = store.load()
    guard !stored.isSubset(of: usedReads) else { return }
    usedReads.formUnion(stored)
    store.save(usedReads)
  }
}
