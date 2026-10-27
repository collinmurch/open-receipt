import XCTest

@testable import open_receipt

@MainActor
final class ReceiptBalanceNoticeTests: XCTestCase {
  func testReceiptThatAddsUpHasNoNotices() {
    let draft = makeDraft(subtotal: 30, tax: 3, total: 33)

    XCTAssertNil(ReceiptBalanceNotice.notice(for: draft))
  }

  func testItemsShortOfSubtotal() throws {
    let draft = makeDraft(subtotal: 35, tax: 3, total: 38)

    let notice = try XCTUnwrap(ReceiptBalanceNotice.notice(for: draft))

    XCTAssertEqual(notice.kind, .items)
    XCTAssertEqual(notice.title, "Items are $5.00 short")
    XCTAssertEqual(
      notice.message,
      "The items come to $30.00, but the receipt’s subtotal is $35.00. An item may be missing or misread."
    )
    XCTAssertEqual(notice.field, .subtotal)
  }

  func testItemsShortOfferAddingTheDifference() throws {
    let draft = makeDraft(subtotal: 35, tax: 3, total: 38)

    let notice = try XCTUnwrap(ReceiptBalanceNotice.notice(for: draft))

    XCTAssertEqual(notice.actions, [.addItem(5), .setSubtotal(30)])
  }

  func testItemsOverOnlyOfferSettingSubtotal() throws {
    let draft = makeDraft(subtotal: 25, tax: 3, total: 28)

    let notice = try XCTUnwrap(ReceiptBalanceNotice.notice(for: draft))

    XCTAssertEqual(notice.title, "Items are $5.00 over")
    XCTAssertEqual(notice.actions, [.setSubtotal(30)])
  }

  func testMisreadSubtotalIsOneNotice() throws {
    let draft = makeDraft(subtotal: 80, tax: 3, total: 33)

    let notice = try XCTUnwrap(ReceiptBalanceNotice.notice(for: draft))

    XCTAssertEqual(notice.kind, .subtotal)
    XCTAssertEqual(notice.actions, [.setSubtotal(30)])
  }

  func testTotalHigherThanItsParts() throws {
    let draft = makeDraft(subtotal: 30, tax: 3, total: 34.50)

    let notice = try XCTUnwrap(ReceiptBalanceNotice.notice(for: draft))

    XCTAssertEqual(notice.kind, .total)
    XCTAssertEqual(notice.title, "Total is $1.50 higher")
    XCTAssertEqual(notice.actions, [.setTotal(33)])
    XCTAssertEqual(notice.field, .total)
  }

  func testTotalLowerThanItsParts() throws {
    let draft = makeDraft(subtotal: 30, tax: 3, total: 32)

    let notice = try XCTUnwrap(ReceiptBalanceNotice.notice(for: draft))

    XCTAssertEqual(notice.title, "Total is $1.00 lower")
  }

  func testTotalNoticeNamesEachPart() throws {
    let draft = makeDraft(subtotal: 30, tax: 3, total: 40)
    draft.tip = 6

    let notice = try XCTUnwrap(ReceiptBalanceNotice.notice(for: draft))

    XCTAssertTrue(notice.message.hasPrefix("The subtotal, tax, and tip come to $39.00"))
  }

  func testTotalNoticeWithoutSubtotalNamesItems() throws {
    let draft = makeDraft(subtotal: 0, total: 31)

    let notice = try XCTUnwrap(ReceiptBalanceNotice.notice(for: draft))

    XCTAssertTrue(notice.message.hasPrefix("The items come to $30.00"))
  }

  func testBothStepsOffShowOnlyItems() {
    let draft = makeDraft(subtotal: 35, tax: 3, total: 40)

    XCTAssertEqual(ReceiptBalanceNotice.notice(for: draft)?.kind, .items)
  }

  func testFixingSubtotalRevealsTotal() {
    let draft = makeDraft(subtotal: 35, tax: 3, total: 40)

    draft.matchSubtotalToItems()

    XCTAssertEqual(ReceiptBalanceNotice.notice(for: draft)?.kind, .total)
  }

  private func makeDraft(subtotal: Double, tax: Double = 0, total: Double) -> ReceiptDraft {
    ReceiptDraft(
      receipt: ParsedReceipt(
        merchantName: "Cafe",
        subtotal: subtotal,
        tax: tax,
        total: total,
        items: [
          ReceiptItem(description: "Coffee", quantity: 1, lineTotal: 10),
          ReceiptItem(description: "Breakfast", quantity: 1, lineTotal: 20),
        ]))
  }
}
