import UIKit
import XCTest

@testable import open_receipt

@MainActor
final class NewReceiptQuickActionsTests: XCTestCase {
  func testEachSourceRoundTripsThroughItsType() {
    for source in NewReceiptSource.allCases {
      XCTAssertEqual(NewReceiptSource(quickActionType: source.quickActionType), source)
    }
  }

  func testTypesAreDistinct() {
    let types = Set(NewReceiptSource.allCases.map(\.quickActionType))

    XCTAssertEqual(types.count, NewReceiptSource.allCases.count)
  }

  func testUnknownTypeIsNotASource() {
    XCTAssertNil(NewReceiptSource(quickActionType: "com.example.unknown"))
  }

  func testPerformQueuesMatchingSource() {
    let quickActions = NewReceiptQuickActions()
    let item = UIApplicationShortcutItem(
      type: NewReceiptSource.importPhotos.quickActionType, localizedTitle: "Import")

    XCTAssertTrue(quickActions.perform(item))
    XCTAssertEqual(quickActions.pending, .importPhotos)
  }

  func testPerformIgnoresUnknownItem() {
    let quickActions = NewReceiptQuickActions()
    let item = UIApplicationShortcutItem(type: "com.example.unknown", localizedTitle: "Unknown")

    XCTAssertFalse(quickActions.perform(item))
    XCTAssertNil(quickActions.pending)
  }

  func testInfoPlistDeclaresEverySource() throws {
    let items = try XCTUnwrap(
      Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]])
    let types = items.compactMap { $0["UIApplicationShortcutItemType"] as? String }

    XCTAssertEqual(types, [NewReceiptSource.scan, .importPhotos, .create].map(\.quickActionType))
  }
}
