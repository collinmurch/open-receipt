import XCTest

@testable import open_receipt

@MainActor
final class ReadingAccessTests: XCTestCase {
  func testAdmitsReadsUpToFreeLimit() {
    let access = makeAccess()

    for key in usedReads() {
      XCTAssertTrue(access.admit(key))
    }
    XCTAssertFalse(access.admit("new"))
  }

  func testAdmittingUsesFreeRead() {
    let access = makeAccess()

    _ = access.admit("a")

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit - 1)
  }

  func testAdmittingSameKeyAgainUsesNoRead() {
    let access = makeAccess()

    _ = access.admit("a")
    _ = access.admit("a")

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit - 1)
  }

  func testRecordedKeyIsAdmittedAtLimit() {
    let access = makeAccess(store: .memory(usedReads()))

    XCTAssertTrue(access.admit("used-1"))
  }

  func testAdmittedReadIsSaved() {
    let store = FreeReadStore.memory()
    let access = makeAccess(store: store)

    _ = access.admit("a")

    XCTAssertEqual(store.load(), ["a"])
  }

  func testReleaseReturnsFreeRead() {
    let store = FreeReadStore.memory()
    let access = makeAccess(store: store)
    _ = access.admit("a")

    access.release("a")

    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit)
    XCTAssertEqual(store.load(), [])
  }

  func testReadsRecordedElsewhereCountBeforeAdmitting() {
    let store = FreeReadStore.memory()
    let access = makeAccess(store: store)

    store.save(usedReads())

    XCTAssertFalse(access.admit("new"))
  }

  func testUnlockedAccessAdmitsWithoutUsingReads() async {
    let access = makeAccess(client: .fixed(isEntitled: true))
    await access.refresh()

    for key in Array(usedReads()) + ["new"] {
      XCTAssertTrue(access.admit(key))
    }
    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit)
  }

  func testAdmitAfterRefreshingFindsPurchase() async {
    let access = makeAccess(client: .fixed(isEntitled: true), store: .memory(usedReads()))

    let isAdmitted = await access.admitAfterRefreshing("new")

    XCTAssertTrue(isAdmitted)
  }

  func testPurchaseUnlocks() async throws {
    let access = makeAccess()

    let outcome = try await access.purchase()

    XCTAssertEqual(outcome, .purchased)
    XCTAssertTrue(access.isUnlocked)
  }

  func testPendingPurchaseStaysLocked() async throws {
    let access = makeAccess(client: .fixed(isEntitled: false, outcome: .pending))

    let outcome = try await access.purchase()

    XCTAssertEqual(outcome, .pending)
    XCTAssertFalse(access.isUnlocked)
  }

  func testCancelledPurchaseStaysLocked() async throws {
    let access = makeAccess(client: .fixed(isEntitled: false, outcome: .cancelled))

    _ = try await access.purchase()

    XCTAssertFalse(access.isUnlocked)
  }

  func testRestoreWithoutPurchaseThrows() async {
    let access = makeAccess()

    do {
      try await access.restore()
      XCTFail("Expected restoring without a purchase to throw")
    } catch {
      XCTAssertEqual(error as? PurchaseError, .nothingToRestore)
    }
  }

  func testRestoreFindsPurchase() async throws {
    let access = makeAccess(client: .fixed(isEntitled: true))

    try await access.restore()

    XCTAssertTrue(access.isUnlocked)
  }

  func testStartRestoresClearedStores() async {
    let device = FreeReadStore.memory(["a"])
    let iCloud = FreeReadStore.memory()
    let access = makeAccess(store: .merged([device, iCloud]))

    await access.start()

    XCTAssertEqual(iCloud.load(), ["a"])
  }

  func testStartFindsTestingChannel() async {
    let access = makeAccess(client: .fixed(isEntitled: false), channel: .testFlight)

    await access.start()

    XCTAssertEqual(access.channel, .testFlight)
    XCTAssertTrue(access.channel.isTesting)
  }

  func testSettingFreeReadsLeftWhileTesting() async {
    let store = FreeReadStore.memory(usedReads())
    let access = makeAccess(
      client: .fixed(isEntitled: false), channel: .testFlight, store: store)
    await access.start()

    access.setFreeReadsLeftForTesting(2)

    XCTAssertEqual(access.freeReadsLeft, 2)
    XCTAssertEqual(store.load().count, ReadingAccess.freeReadLimit - 2)
  }

  func testSettingFreeReadsLeftCanUseReads() async {
    let access = makeAccess(client: .fixed(isEntitled: false), channel: .testFlight)
    await access.start()

    access.setFreeReadsLeftForTesting(0)

    XCTAssertEqual(access.freeReadsLeft, 0)
  }

  func testSettingFreeReadsLeftKeepsRecordedReads() async {
    let access = makeAccess(
      client: .fixed(isEntitled: false), channel: .testFlight, store: .memory(["recorded"]))
    await access.start()

    access.setFreeReadsLeftForTesting(ReadingAccess.freeReadLimit - 2)

    XCTAssertTrue(access.admit("recorded"))
    XCTAssertEqual(access.freeReadsLeft, ReadingAccess.freeReadLimit - 2)
  }

  func testSettingFreeReadsLeftDoesNothingInAppStore() async {
    let store = FreeReadStore.memory(usedReads())
    let access = makeAccess(client: .fixed(isEntitled: false), channel: .appStore, store: store)
    await access.start()

    access.setFreeReadsLeftForTesting(ReadingAccess.freeReadLimit)

    XCTAssertEqual(access.freeReadsLeft, 0)
    XCTAssertEqual(store.load(), usedReads())
  }

  func testRemovedPurchaseLocksWhileTesting() async {
    let access = makeAccess(client: .fixed(isEntitled: true), channel: .testFlight)
    await access.start()

    await access.removePurchaseForTesting()

    XCTAssertFalse(access.isUnlocked)
  }

  func testRemovingPurchaseDoesNothingInProduction() async {
    let access = makeAccess(client: .fixed(isEntitled: true), channel: .appStore)
    await access.start()

    await access.removePurchaseForTesting()

    XCTAssertTrue(access.isUnlocked)
  }

  func testRemovedPurchaseCountsInProduction() async {
    let defaults = isolatedDefaults()
    let testing = makeAccess(
      client: .fixed(isEntitled: true), channel: .testFlight, defaults: defaults)
    await testing.start()
    await testing.removePurchaseForTesting()
    let production = makeAccess(
      client: .fixed(isEntitled: true), channel: .appStore, defaults: defaults)

    await production.start()

    XCTAssertTrue(production.isUnlocked)
  }

  func testBuyingAgainReturnsRemovedPurchase() async throws {
    let access = makeAccess(client: .fixed(isEntitled: true), channel: .testFlight)
    await access.start()
    await access.removePurchaseForTesting()

    _ = try await access.purchase()

    XCTAssertTrue(access.isUnlocked)
  }

  func testRestoringReturnsRemovedPurchase() async throws {
    let access = makeAccess(client: .fixed(isEntitled: true), channel: .testFlight)
    await access.start()
    await access.removePurchaseForTesting()

    try await access.restore()

    XCTAssertTrue(access.isUnlocked)
  }

  /// A read key for every free read.
  private func usedReads() -> Set<String> {
    Set((1...ReadingAccess.freeReadLimit).map { "used-\($0)" })
  }

  private func makeAccess(
    client: PurchaseClient = .fixed(isEntitled: false),
    channel: BuildChannel = .appStore,
    store: FreeReadStore = .memory(),
    defaults: UserDefaults? = nil
  ) -> ReadingAccess {
    ReadingAccess(
      client: client,
      store: store,
      defaults: defaults ?? isolatedDefaults(),
      resolveChannel: { channel })
  }
}
