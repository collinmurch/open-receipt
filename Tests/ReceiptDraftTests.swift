#if !SWIFT_PACKAGE
  import XCTest
  @testable import open_receipt

  @MainActor
  final class ReceiptDraftTests: XCTestCase {
    func testNewDraftStartsWithCurrentUser() {
      let draft = makeDraft()

      XCTAssertEqual(draft.participants.count, 1)
      XCTAssertEqual(draft.participants.first?.source, .currentUser(contactIdentifier: nil))
      XCTAssertEqual(draft.participants.first?.displayName, "Me")
    }

    func testNewDraftStartsWithOwner() {
      let draft = ReceiptDraft(
        receipt: ParsedReceipt(),
        owner: ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

      XCTAssertEqual(draft.currentUser?.source, .currentUser(contactIdentifier: "me"))
      XCTAssertEqual(draft.currentUser?.displayName, "Alex")
    }

    func testSetOwnerUpdatesCurrentUser() {
      let draft = makeDraft()
      let currentUserID = draft.currentUser?.id

      draft.setOwner(ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

      XCTAssertEqual(draft.currentUser?.id, currentUserID)
      XCTAssertEqual(draft.currentUser?.source, .currentUser(contactIdentifier: "me"))
      XCTAssertEqual(draft.currentUser?.displayName, "Alex")
    }

    func testSetOwnerKeepsCurrentUserAssignments() throws {
      let draft = makeDraft()
      let currentUserID = try XCTUnwrap(draft.currentUser?.id)
      draft.items[0].participantIDs = [currentUserID]

      draft.setOwner(ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

      XCTAssertEqual(draft.items[0].participantIDs, [currentUserID])
    }

    func testSetOwnerMarksDurableChange() {
      let draft = makeDraft()
      let revision = draft.persistenceRevision

      draft.setOwner(ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

      XCTAssertNotEqual(draft.persistenceRevision, revision)
    }

    func testClearingOwnerRestoresDefaultName() {
      let draft = makeDraft()
      draft.setOwner(ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

      draft.setOwner(nil)

      XCTAssertEqual(draft.currentUser?.source, .currentUser(contactIdentifier: nil))
      XCTAssertEqual(draft.currentUser?.displayName, "Me")
    }

    func testOwnerIsNotMatchedAsContactParticipant() {
      let draft = makeDraft()

      draft.setOwner(ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))

      XCTAssertNil(draft.participant(forContactIdentifier: "me"))
    }

    func testOwnerAvatarUpdatesByContactIdentifier() {
      let draft = makeDraft()
      draft.setOwner(ReceiptOwner(contactIdentifier: "me", displayName: "Alex"))
      let avatar = Data([1, 2, 3])

      draft.updateAvatar(avatar, forContactIdentifier: "me")

      XCTAssertEqual(draft.currentUser?.avatarData, avatar)
    }

    func testNewDraftConvertsReceiptItems() {
      let draft = makeDraft()

      XCTAssertEqual(draft.items.count, 1)
      XCTAssertEqual(draft.items.first?.description, "Coffee")
      XCTAssertEqual(draft.items.first?.lineTotal, 4.50)
      XCTAssertEqual(draft.items.first?.participantIDs, [])
    }

    func testNewDraftTreatsZeroAdjustmentsAsMissing() {
      let draft = makeDraft()

      XCTAssertTrue(draft.adjustments.isEmpty)
    }

    func testNewDraftKeepsSelectedBackgroundStyle() {
      let draft = ReceiptDraft(
        receipt: ParsedReceipt(total: 4.50),
        backgroundStyle: .peach)

      XCTAssertEqual(draft.backgroundStyle, .peach)
    }

    func testNewDraftIncludesNonzeroTax() {
      let receipt = ParsedReceipt(subtotal: 4.50, tax: 0.50, total: 5)

      let draft = ReceiptDraft(receipt: receipt)

      XCTAssertTrue(draft.adjustments.contains(.tax))
    }

    func testContactIsDeduplicatedByIdentifier() {
      let draft = makeDraft()
      let contact = ContactSummary(identifier: "contact-1", displayName: "Sam Lee")

      draft.addContact(contact)
      draft.addContact(contact)

      XCTAssertEqual(draft.participants.count, 2)
    }

    func testContactSnapshotUpdatesWhenAddedAgain() {
      let draft = makeDraft()
      draft.addContact(ContactSummary(identifier: "contact-1", displayName: "Sam Lee"))

      draft.addContact(ContactSummary(identifier: "contact-1", displayName: "Samantha Lee"))

      XCTAssertEqual(
        draft.participant(forContactIdentifier: "contact-1")?.displayName, "Samantha Lee")
    }

    func testManualParticipantTrimsName() {
      let draft = makeDraft()

      let participant = draft.addManualParticipant(named: "  Jordan  ")

      XCTAssertEqual(participant?.displayName, "Jordan")
    }

    func testManualParticipantRejectsEmptyName() {
      let draft = makeDraft()

      XCTAssertNil(draft.addManualParticipant(named: "  \n "))
      XCTAssertEqual(draft.participants.count, 1)
    }

    func testCurrentUserCannotBeRemoved() throws {
      let draft = makeDraft()
      let currentUserID = try XCTUnwrap(draft.participants.first?.id)

      draft.removeParticipant(id: currentUserID)

      XCTAssertEqual(draft.participants.count, 1)
    }

    func testRemovingParticipantClearsItemAssignments() throws {
      let draft = makeDraft()
      let participant = try XCTUnwrap(draft.addManualParticipant(named: "Jordan"))
      draft.items[0].participantIDs.insert(participant.id)

      draft.removeParticipant(id: participant.id)

      XCTAssertTrue(draft.items[0].participantIDs.isEmpty)
    }

    func testToggleAssignmentAddsMultipleParticipants() throws {
      let draft = makeDraft()
      let currentUserID = try XCTUnwrap(draft.participants.first?.id)
      let participant = try XCTUnwrap(draft.addManualParticipant(named: "Jordan"))
      let itemID = try XCTUnwrap(draft.items.first?.id)

      draft.toggleAssignment(of: [currentUserID, participant.id], to: itemID)

      XCTAssertEqual(draft.items[0].participantIDs, [currentUserID, participant.id])
    }

    func testToggleAssignmentRemovesSelectedParticipantsWhenAllAreAssigned() throws {
      let draft = makeDraft()
      let currentUserID = try XCTUnwrap(draft.participants.first?.id)
      let itemID = try XCTUnwrap(draft.items.first?.id)
      draft.items[0].participantIDs = [currentUserID]

      draft.toggleAssignment(of: [currentUserID], to: itemID)

      XCTAssertTrue(draft.items[0].participantIDs.isEmpty)
    }

    func testToggleAssignmentCompletesPartialSelection() throws {
      let draft = makeDraft()
      let currentUserID = try XCTUnwrap(draft.participants.first?.id)
      let participant = try XCTUnwrap(draft.addManualParticipant(named: "Jordan"))
      let itemID = try XCTUnwrap(draft.items.first?.id)
      draft.items[0].participantIDs = [currentUserID]

      draft.toggleAssignment(of: [currentUserID, participant.id], to: itemID)

      XCTAssertEqual(draft.items[0].participantIDs, [currentUserID, participant.id])
    }

    func testToggleAssignmentIgnoresRemovedParticipant() throws {
      let draft = makeDraft()
      let participant = try XCTUnwrap(draft.addManualParticipant(named: "Jordan"))
      let itemID = try XCTUnwrap(draft.items.first?.id)
      draft.removeParticipant(id: participant.id)

      draft.toggleAssignment(of: [participant.id], to: itemID)

      XCTAssertTrue(draft.items[0].participantIDs.isEmpty)
    }

    func testNewDraftIsNotCompleted() {
      let draft = makeDraft()

      XCTAssertFalse(draft.isCompleted)
    }

    func testCompletingDraftAdvancesPersistenceRevisionOnce() {
      let draft = makeDraft()
      let revision = draft.persistenceRevision

      draft.complete()
      draft.complete()

      XCTAssertTrue(draft.isCompleted)
      XCTAssertEqual(draft.persistenceRevision, revision + 1)
    }

    func testRecordingRequestStoresDateForParticipant() throws {
      let draft = makeDraft()
      let participant = try XCTUnwrap(draft.addManualParticipant(named: "Jordan"))
      let date = Date(timeIntervalSince1970: 1_700_000_000)

      draft.recordRequest(for: participant.id, at: date)

      XCTAssertEqual(
        draft.participants.first { $0.id == participant.id }?.lastRequestedAt,
        date)
    }

    func testRecordingRequestAdvancesPersistenceRevision() throws {
      let draft = makeDraft()
      let participant = try XCTUnwrap(draft.addManualParticipant(named: "Jordan"))
      let revision = draft.persistenceRevision

      draft.recordRequest(for: participant.id)

      XCTAssertEqual(draft.persistenceRevision, revision + 1)
    }

    func testRecordingRequestIgnoresUnknownParticipant() {
      let draft = makeDraft()
      let revision = draft.persistenceRevision

      draft.recordRequest(for: UUID())

      XCTAssertEqual(draft.persistenceRevision, revision)
    }

    func testWarningsUpdateAfterCurrencyIsFixed() {
      let receipt = ParsedReceipt(
        merchantName: "Cafe",
        subtotal: 4.50,
        total: 4.50,
        currency: "US",
        warnings: ["Currency is not a three-letter ISO code."])
      let draft = ReceiptDraft(receipt: receipt)

      draft.currency = "USD"

      XCTAssertFalse(draft.warnings.contains("Currency is not a three-letter ISO code."))
    }

    func testWarningsRefreshAfterEditFollowingRead() {
      let draft = ReceiptDraft(receipt: ParsedReceipt(merchantName: "Cafe", total: 4.50))
      XCTAssertFalse(draft.warnings.contains("Currency is not a three-letter ISO code."))

      draft.currency = "US"

      XCTAssertTrue(draft.warnings.contains("Currency is not a three-letter ISO code."))
    }

    func testWarningsKeepExtractionWarning() {
      let receipt = ParsedReceipt(
        merchantName: "Cafe",
        subtotal: 4.50,
        total: 4.50,
        warnings: ["The receipt image is blurry."])
      let draft = ReceiptDraft(receipt: receipt)

      XCTAssertTrue(draft.warnings.contains("The receipt image is blurry."))
    }

    func testWarningsDoNotDuplicateTotalReconciliation() {
      let receipt = ParsedReceipt(
        merchantName: "Cafe",
        subtotal: 10,
        tax: 1,
        total: 20,
        warnings: [ReceiptValidator.totalReconciliationWarning])
      let draft = ReceiptDraft(receipt: receipt)

      XCTAssertFalse(draft.warnings.contains(ReceiptValidator.totalReconciliationWarning))
    }

    func testRescanKeepsParticipants() throws {
      let previous = makeDraft()
      previous.addManualParticipant(named: "Sam")

      let rescanned = ReceiptDraft(receipt: rescannedReceipt(), replacing: previous)

      XCTAssertEqual(rescanned.participants, previous.participants)
    }

    func testRescanKeepsIdentifierAndBackgroundStyle() {
      let previous = makeDraft()

      let rescanned = ReceiptDraft(receipt: rescannedReceipt(), replacing: previous)

      XCTAssertEqual(rescanned.id, previous.id)
      XCTAssertEqual(rescanned.backgroundStyle, previous.backgroundStyle)
    }

    func testRescanReplacesItems() {
      let previous = makeDraft()

      let rescanned = ReceiptDraft(receipt: rescannedReceipt(), replacing: previous)

      XCTAssertEqual(rescanned.items.map(\.description), ["Tea", "Scone"])
    }

    func testRescanReplacesPrintedTotals() {
      let previous = makeDraft()

      let rescanned = ReceiptDraft(receipt: rescannedReceipt(), replacing: previous)

      XCTAssertEqual(rescanned.subtotal, 9)
      XCTAssertEqual(rescanned.total, 9.75)
    }

    func testRescanClearsItemAssignments() throws {
      let previous = makeDraft()
      let person = try XCTUnwrap(previous.addManualParticipant(named: "Sam"))
      let item = try XCTUnwrap(previous.items.first)
      previous.toggleAssignment(of: [person.id], to: item.id)

      let rescanned = ReceiptDraft(receipt: rescannedReceipt(), replacing: previous)

      XCTAssertTrue(rescanned.items.allSatisfy { $0.participantIDs.isEmpty })
    }

    func testRescanKeepsEnteredTip() {
      let previous = makeDraft()
      previous.tip = 2

      let rescanned = ReceiptDraft(receipt: rescannedReceipt(), replacing: previous)

      XCTAssertEqual(rescanned.tip, 2)
    }

    func testRescanPrefersPrintedTip() {
      let previous = makeDraft()
      previous.tip = 2

      let rescanned = ReceiptDraft(receipt: rescannedReceipt(tip: 3), replacing: previous)

      XCTAssertEqual(rescanned.tip, 3)
    }

    func testRescanKeepsSplitMethod() {
      let previous = makeDraft()
      previous.adjustmentSplitMethod = .even

      let rescanned = ReceiptDraft(receipt: rescannedReceipt(), replacing: previous)

      XCTAssertEqual(rescanned.adjustmentSplitMethod, .even)
    }

    func testRescanStartsIncomplete() {
      let previous = makeDraft()
      previous.complete()

      let rescanned = ReceiptDraft(receipt: rescannedReceipt(), replacing: previous)

      XCTAssertFalse(rescanned.isCompleted)
    }

    private func rescannedReceipt(tip: Double = 0) -> ParsedReceipt {
      ParsedReceipt(
        subtotal: 9,
        tax: 0.75,
        tip: tip,
        total: 9.75 + tip,
        currency: "USD",
        items: [
          ReceiptItem(description: "Tea", quantity: 1, lineTotal: 4),
          ReceiptItem(description: "Scone", quantity: 1, lineTotal: 5),
        ])
    }

    private func makeDraft() -> ReceiptDraft {
      ReceiptDraft(
        receipt: ParsedReceipt(
          merchantName: "Cafe",
          subtotal: 4.50,
          total: 4.50,
          items: [ReceiptItem(description: "Coffee", quantity: 1, lineTotal: 4.50)]))
    }
  }
#endif
