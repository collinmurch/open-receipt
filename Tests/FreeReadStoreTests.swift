import XCTest

@testable import open_receipt

final class FreeReadStoreTests: XCTestCase {
  func testMergedStoreLoadsEveryStore() {
    let store = FreeReadStore.merged([.memory(["a"]), .memory(["b"])])

    XCTAssertEqual(store.load(), ["a", "b"])
  }

  func testMergedStoreSavesToEveryStore() {
    let device = FreeReadStore.memory()
    let iCloud = FreeReadStore.memory()

    FreeReadStore.merged([device, iCloud]).save(["a"])

    XCTAssertEqual(device.load(), ["a"])
    XCTAssertEqual(iCloud.load(), ["a"])
  }

  func testMergedStoreKeepsReadsWhenOneStoreIsCleared() {
    let device = FreeReadStore.memory(["a"])
    let iCloud = FreeReadStore.memory(["a"])
    let store = FreeReadStore.merged([device, iCloud])

    device.save([])

    XCTAssertEqual(store.load(), ["a"])
  }
}
