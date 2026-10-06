import XCTest

@testable import open_receipt

@MainActor
final class ReceiptFlowSavingTests: XCTestCase, ReceiptFlowTesting {
  func testAutosaveWritesChangedDraft() async throws {
    let recorder = SaveRecorder()
    let (model, storage) = await reviewingModel(merchantName: "Saved", recorder: recorder)
    let draft = try XCTUnwrap(model.reviewingDraft)

    draft.merchantName = "Updated"
    await model.autosave(storage: storage)

    let saved = await recorder.documents
    XCTAssertEqual(saved.last?.receipt?.merchant.name, "Updated")
  }

  func testFlushWritesWithoutDebounce() async throws {
    let recorder = SaveRecorder()
    let (model, storage) = await reviewingModel(merchantName: "Saved", recorder: recorder)
    let draft = try XCTUnwrap(model.reviewingDraft)
    draft.total = 12

    let didSave = await model.flush(storage: storage)

    XCTAssertTrue(didSave)
    let saved = await recorder.documents
    XCTAssertEqual(saved.last?.receipt?.amounts.total.value, "12.0")
  }

  func testSaveKeepsReviewingSameDraft() async throws {
    let (model, storage) = await reviewingModel(merchantName: "Saved")
    let draft = try XCTUnwrap(model.reviewingDraft)
    draft.merchantName = "Updated"

    _ = await model.flush(storage: storage)

    XCTAssertTrue(model.reviewingDraft === draft)
    XCTAssertEqual(model.document?.receipt?.merchant.name, "Updated")
  }

  func testFlushWithoutChangesDoesNotSave() async {
    let recorder = SaveRecorder()
    let (model, storage) = await reviewingModel(merchantName: "Saved", recorder: recorder)

    _ = await model.flush(storage: storage)

    let saved = await recorder.documents
    XCTAssertTrue(saved.isEmpty)
  }
}
