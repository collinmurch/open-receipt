import XCTest

@testable import open_receipt

@MainActor
final class ReceiptFlowCreateTests: XCTestCase, ReceiptFlowTesting {
  func testCreateInputStartsInCreatingPhase() {
    let id = UUID()
    let model = ReceiptFlowModel(input: .create(id: id))

    guard case .creating(let creatingID) = model.phase else {
      return XCTFail("Expected creating phase")
    }
    XCTAssertEqual(creatingID, id)
  }

  func testCreateInputCreatesBlankReviewDraft() async throws {
    let id = UUID()
    let document = blankDocument(id: id)
    let storage = storage(document: document)
    let model = ReceiptFlowModel(input: .create(id: id))

    await model.performWork(using: center(storage: storage), storage: storage)

    let draft = try XCTUnwrap(model.reviewingDraft)
    XCTAssertEqual(model.document?.id, id)
    XCTAssertEqual(model.document?.scan.source, .manual)
    XCTAssertEqual(draft.merchantName, "")
    XCTAssertTrue(draft.items.isEmpty)
  }

  func testCreateInputAppliesOwner() async {
    let id = UUID()
    let storage = storage(document: blankDocument(id: id))
    let model = ReceiptFlowModel(input: .create(id: id))

    await model.performWork(using: center(storage: storage), storage: storage) {
      ReceiptOwner(contactIdentifier: "me", displayName: "Alex")
    }

    XCTAssertEqual(
      model.reviewingDraft?.currentUser?.source, .currentUser(contactIdentifier: "me"))
    XCTAssertEqual(model.reviewingDraft?.currentUser?.displayName, "Alex")
  }

  func testCreateInputWithoutOwnerKeepsDefaultName() async {
    let id = UUID()
    let storage = storage(document: blankDocument(id: id))
    let model = ReceiptFlowModel(input: .create(id: id))

    await model.performWork(using: center(storage: storage), storage: storage)

    XCTAssertEqual(model.reviewingDraft?.currentUser?.displayName, "Me")
  }

  func testCreateInputUsesSuppliedBackgroundStyle() {
    let model = ReceiptFlowModel(input: .create(backgroundStyle: .peach))

    XCTAssertEqual(model.backgroundStyle, .peach)
  }

  func testCreatedReceiptStartsInEditing() async {
    let id = UUID()
    let storage = storage(document: blankDocument(id: id))
    let model = ReceiptFlowModel(input: .create(id: id))

    await model.performWork(using: center(storage: storage), storage: storage)

    XCTAssertTrue(model.startsInEditing)
  }
}
