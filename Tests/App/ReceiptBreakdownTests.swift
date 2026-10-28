import XCTest

@testable import open_receipt

@MainActor
final class ReceiptBreakdownTests: XCTestCase {
  func testPersonTitleNamesMerchantAndPerson() throws {
    let draft = makeSplitDraft()
    let share = draft.splitCalculation.participantShares[1]

    let breakdown = try XCTUnwrap(draft.breakdown(for: share, accentScheme: .light))

    XCTAssertEqual(breakdown.title, "Cafe – Sam")
  }

  func testGroupTitleIsMerchant() throws {
    let breakdown = try XCTUnwrap(makeSplitDraft().groupBreakdown(accentScheme: .light))

    XCTAssertEqual(breakdown.title, "Cafe")
  }

  func testTitleFallsBackWithoutMerchant() throws {
    let draft = makeSplitDraft()
    draft.merchantName = "  "

    let breakdown = try XCTUnwrap(draft.groupBreakdown(accentScheme: .light))

    XCTAssertEqual(breakdown.title, "Receipt")
  }

  func testFileNameReplacesPathSeparators() throws {
    let draft = makeSplitDraft()
    draft.merchantName = "Bar/Grill: Downtown"

    let breakdown = try XCTUnwrap(draft.groupBreakdown(accentScheme: .light))

    XCTAssertEqual(breakdown.fileName, "Bar-Grill- Downtown")
  }

  func testGroupIncludesEveryone() throws {
    let breakdown = try XCTUnwrap(makeSplitDraft().groupBreakdown(accentScheme: .light))

    guard case .group(let shares) = breakdown.content else { return XCTFail("Expected a group") }
    XCTAssertEqual(shares.count, 2)
  }

  func testGroupTotalSumsShares() throws {
    let breakdown = try XCTUnwrap(makeSplitDraft().groupBreakdown(accentScheme: .light))

    XCTAssertEqual(breakdown.total, 40)
  }

  func testPersonMessageNamesMerchantAndShare() throws {
    let draft = makeSplitDraft()
    let share = draft.splitCalculation.participantShares[1]

    let breakdown = try XCTUnwrap(draft.breakdown(for: share, accentScheme: .light))

    XCTAssertEqual(breakdown.messageBody, "Here’s your share of Cafe: $30.00.")
  }

  func testGroupMessageNamesMerchantAndTotal() throws {
    let breakdown = try XCTUnwrap(makeSplitDraft().groupBreakdown(accentScheme: .light))

    XCTAssertEqual(breakdown.messageBody, "Here’s how we split Cafe: $40.00 total.")
  }

  func testAllBreakdownsLeadWithOverview() throws {
    let breakdowns = try XCTUnwrap(makeSplitDraft().allBreakdowns(accentScheme: .light))

    guard case .group = breakdowns.first?.content else { return XCTFail("Expected the overview") }
  }

  func testAllBreakdownsIncludeEachPerson() throws {
    let breakdowns = try XCTUnwrap(makeSplitDraft().allBreakdowns(accentScheme: .light))

    XCTAssertEqual(breakdowns.count, 3)
    XCTAssertEqual(breakdowns.last?.title, "Cafe – Sam")
  }

  func testUnassignedItemsWithholdAllBreakdowns() {
    let draft = makeSplitDraft()
    draft.items[0].participantIDs = []

    XCTAssertNil(draft.allBreakdowns(accentScheme: .light))
  }

  func testUnassignedItemsWithholdBreakdown() {
    let draft = makeSplitDraft()
    draft.items[0].participantIDs = []

    XCTAssertNil(draft.groupBreakdown(accentScheme: .light))
  }

  func testRendersPNGAtCardWidth() async throws {
    let breakdown = try XCTUnwrap(makeSplitDraft().groupBreakdown(accentScheme: .light))

    let png = await ReceiptBreakdownRenderer.pngData(for: breakdown)
    let data = try XCTUnwrap(png)
    let image = try XCTUnwrap(UIImage(data: data)?.cgImage)

    XCTAssertEqual(
      CGFloat(image.width), ReceiptBreakdownRenderer.width * ReceiptBreakdownRenderer.scale)
  }

  func testRendersSinglePagePDF() throws {
    let breakdown = try XCTUnwrap(makeSplitDraft().groupBreakdown(accentScheme: .light))

    let data = try XCTUnwrap(ReceiptBreakdownRenderer.pdfData(for: breakdown))
    let document = try XCTUnwrap(CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init))

    XCTAssertEqual(document.numberOfPages, 1)
  }

  private func makeSplitDraft() -> ReceiptDraft {
    let draft = ReceiptDraft.fixture(items: ["Coffee": 10, "Breakfast": 30])
    let secondPerson = draft.addManualParticipant(named: "Sam")
    draft.items[0].participantIDs = [draft.ownerID]
    draft.items[1].participantIDs = [secondPerson.id]
    return draft
  }
}
