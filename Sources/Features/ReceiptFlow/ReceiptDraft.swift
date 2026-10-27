import Foundation
import Observation

@MainActor
@Observable
final class ReceiptDraft {
  let id: UUID
  let backgroundStyle: ReceiptBackgroundStyle
  var merchantName: String { didSet { markPersistedChange() } }
  var date: String { didSet { markPersistedChange() } }
  var subtotal: Double { didSet { markDurableChange() } }
  var adjustments: ReceiptTotalAdjustments { didSet { markDurableChange() } }
  var total: Double { didSet { markDurableChange() } }
  var currency: String { didSet { markDurableChange() } }
  var payment: ReceiptPayment? { didSet { markPersistedChange() } }
  var items: [ReceiptDraftItem] { didSet { markDurableChange() } }
  var adjustmentSplitMethod: ReceiptAdjustmentSplitMethod {
    didSet { markDurableChange() }
  }
  /// The order tax, tip, and savings are listed in. The tip is a percentage of the subtotal with
  /// whatever is listed above it. Change it with `setAdjustmentOrder(_:percentages:)` to carry a
  /// suggested tip's percentage over.
  var adjustmentOrder: [ReceiptTotalAdjustment] { didSet { markPersistedChange() } }
  private(set) var isCompleted: Bool
  /// The tax and tip still to ask about, in the order they're asked.
  private(set) var unconfirmedAdjustments: [ReceiptTotalAdjustment] {
    didSet { markPersistedChange() }
  }
  private(set) var participants: [ReceiptParticipant]
  private(set) var persistenceRevision = 0
  @ObservationIgnored private var splitCalculationCache: ReceiptSplitCalculation?
  @ObservationIgnored private var balanceCache: ReceiptBalance?
  /// Counts changes to what the split and balance are worked out from, so reading either
  /// observes them.
  private var durableRevision = 0
  @ObservationIgnored private var issuesCache: (revision: Int, issues: [ReceiptIssue])?

  init(
    receipt: ParsedReceipt,
    id: UUID = UUID(),
    owner: ReceiptOwner? = nil,
    backgroundStyle: ReceiptBackgroundStyle = .random(),
    adjustmentSplitMethod: ReceiptAdjustmentSplitMethod = AdjustmentSplitSettings.defaultMethod(),
    adjustmentOrder: [ReceiptTotalAdjustment] = ReceiptTotalAdjustment.order(
      tipBase: TipSettings.base())
  ) {
    self.id = id
    self.backgroundStyle = backgroundStyle
    merchantName = receipt.merchantName
    date = receipt.date
    subtotal = receipt.subtotal
    adjustments = ReceiptTotalAdjustments(
      tax: receipt.tax,
      tip: receipt.tip,
      savings: receipt.savings)
    total = receipt.total
    currency = receipt.currency
    payment = receipt.payment
    items = receipt.items.map { ReceiptDraftItem(item: $0) }
    self.adjustmentSplitMethod = adjustmentSplitMethod
    self.adjustmentOrder = adjustmentOrder
    isCompleted = false
    unconfirmedAdjustments = []
    participants = [.currentUser(owner: owner)]
  }

  /// Creates a draft from a new recognition of `previous`'s receipt. People, colors, the split
  /// method, the adjustments' order, and an entered tip carry over; items, printed totals, and
  /// assignments are replaced.
  convenience init(receipt: ParsedReceipt, replacing previous: ReceiptDraft) {
    self.init(receipt: receipt, id: previous.id, backgroundStyle: previous.backgroundStyle)
    participants = previous.participants
    adjustmentSplitMethod = previous.adjustmentSplitMethod
    adjustmentOrder = previous.adjustmentOrder
    if !adjustments.contains(.tip), let tip = previous.adjustments[.tip] {
      adjustments[.tip] = tip
    }
  }

  init(document: ReceiptDocument) throws {
    let state = try ReceiptDraftPersistenceState(document: document)
    id = state.id
    backgroundStyle = state.backgroundStyle
    merchantName = state.merchantName
    date = state.date
    subtotal = state.subtotal
    adjustments = state.adjustments
    total = state.total
    currency = state.currency
    payment = state.payment
    items = state.items
    adjustmentSplitMethod = state.adjustmentSplitMethod
    adjustmentOrder = state.adjustmentOrder
    isCompleted = state.isCompleted
    unconfirmedAdjustments = state.unconfirmedAdjustments
    participants = state.participants
  }

  /// The tax. Setting it moves a total that added up along with it, as do `tip` and `savings`.
  var tax: Double {
    get { adjustments[.tax] ?? 0 }
    set { keepingBalance { adjustments[.tax] = newValue } }
  }

  var tip: Double {
    get { adjustments[.tip] ?? 0 }
    set { keepingBalance { adjustments[.tip] = newValue } }
  }

  var savings: Double {
    get { adjustments[.savings] ?? 0 }
    set { keepingBalance { adjustments[.savings] = newValue } }
  }

  /// What needs fixing in the current values. Totals that don't add up aren't an issue, because
  /// the totals section explains them with a `ReceiptBalanceNotice`.
  var issues: [ReceiptIssue] {
    let revision = persistenceRevision
    if let issuesCache, issuesCache.revision == revision {
      return issuesCache.issues
    }
    let issues = uncachedIssues()
    issuesCache = (revision, issues)
    return issues
  }

  var splitCalculation: ReceiptSplitCalculation {
    _ = durableRevision
    if let splitCalculationCache { return splitCalculationCache }
    let calculation = ReceiptSplitCalculator.calculate(splitInput)
    splitCalculationCache = calculation
    return calculation
  }

  /// How the receipt's amounts add up.
  var balance: ReceiptBalance {
    _ = durableRevision
    if let balanceCache { return balanceCache }
    let balance = ReceiptBalance(splitInput)
    balanceCache = balance
    return balance
  }

  @discardableResult
  func addPerson(_ person: Person) -> ReceiptParticipant {
    if let index = participants.firstIndex(where: { $0.personID == person.id }) {
      if participants[index].displayName != person.displayName {
        participants[index].displayName = person.displayName
        markDurableChange()
      }
      return participants[index]
    }

    let source = person.contactIdentifier.map(ReceiptParticipant.Source.contact) ?? .manual
    let participant = ReceiptParticipant(
      id: UUID(),
      personID: person.id,
      source: source,
      displayName: person.displayName)
    participants.append(participant)
    markDurableChange()
    return participant
  }

  func participant(forPersonID id: Person.ID) -> ReceiptParticipant? {
    participants.first { $0.personID == id }
  }

  func removeParticipant(id: ReceiptParticipant.ID) {
    guard let participant = participants.first(where: { $0.id == id }),
      !participant.source.isCurrentUser
    else { return }
    participants.removeAll { $0.id == id }
    var items = self.items
    for index in items.indices {
      items[index].participantIDs.remove(id)
    }
    self.items = items
    markDurableChange()
  }

  func recordRequest(for participantID: ReceiptParticipant.ID, at date: Date = Date()) {
    guard let index = participants.firstIndex(where: { $0.id == participantID }) else { return }
    participants[index].lastRequestedAt = date
    markDurableChange()
  }

  func toggleAssignment(
    of participantIDs: Set<ReceiptParticipant.ID>, to itemID: ReceiptDraftItem.ID
  ) {
    let validParticipantIDs = participantIDs.intersection(participants.map(\.id))
    guard !validParticipantIDs.isEmpty,
      let itemIndex = items.firstIndex(where: { $0.id == itemID })
    else { return }

    if validParticipantIDs.isSubset(of: items[itemIndex].participantIDs) {
      items[itemIndex].participantIDs.subtract(validParticipantIDs)
    } else {
      items[itemIndex].participantIDs.formUnion(validParticipantIDs)
    }
  }

  func clearAssignments(of itemID: ReceiptDraftItem.ID) {
    guard let itemIndex = items.firstIndex(where: { $0.id == itemID }),
      !items[itemIndex].participantIDs.isEmpty
    else { return }
    items[itemIndex].participantIDs = []
  }

  /// Applies `sweep`'s assignments in one change, so the split recalculates once per step.
  func apply(_ sweep: ReceiptItemSweep) {
    let swept = sweep.applied(to: items)
    if swept != items { items = swept }
  }

  func participants(assignedTo item: ReceiptDraftItem) -> [ReceiptParticipant] {
    participants.filter { item.participantIDs.contains($0.id) }
  }

  /// The first item no one on the receipt shares, which the split can't place yet.
  var firstUnassignedItemID: ReceiptDraftItem.ID? {
    items.first { participants(assignedTo: $0).isEmpty }?.id
  }

  func participant(forContactIdentifier identifier: String) -> ReceiptParticipant? {
    participants.first { $0.source == .contact(identifier: identifier) }
  }

  var currentUser: ReceiptParticipant? {
    participants.first { $0.source.isCurrentUser }
  }

  /// Makes `owner` the person using the app on this receipt, or restores the default name.
  func setOwner(_ owner: ReceiptOwner?) {
    guard let index = participants.firstIndex(where: { $0.source.isCurrentUser }) else { return }
    participants[index].source = .currentUser(contactIdentifier: owner?.contactIdentifier)
    participants[index].displayName =
      owner?.displayName ?? ReceiptParticipant.defaultCurrentUserName
    markDurableChange()
  }

  /// Trims what was typed, assigning only fields that change so an untouched receipt isn't saved.
  func normalizeEditableFields() {
    let merchantName = self.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    if merchantName != self.merchantName { self.merchantName = merchantName }
    let date = self.date.trimmingCharacters(in: .whitespacesAndNewlines)
    if date != self.date { self.date = date }
    let currency = normalizedCurrency
    if currency != self.currency { self.currency = currency }
    let items = self.items.map { item in
      var item = item
      item.description = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
      return item
    }
    if items != self.items { self.items = items }
  }

  /// Asks about the tax and tip a read didn't find. A read that found no items has nothing to
  /// work them out from, so it asks nothing and the receipt opens to be fixed.
  func askAboutMissingAdjustments() {
    guard itemsTotal > 0 else {
      unconfirmedAdjustments = []
      return
    }
    unconfirmedAdjustments = ReceiptTotalAdjustment.confirmable.filter {
      !adjustments.contains($0)
    }
  }

  /// Records `amount` of `adjustment` and stops asking about it. A total that added up keeps
  /// adding up, so a tip left after the receipt was printed raises it.
  func confirm(_ adjustment: ReceiptTotalAdjustment, amount: Double) {
    addAdjustment(adjustment, amount: amount)
    stopAsking(about: adjustment)
  }

  /// Stops asking about `adjustment` without recording an amount, for a receipt that has none.
  func stopAsking(about adjustment: ReceiptTotalAdjustment) {
    unconfirmedAdjustments.removeAll { $0 == adjustment }
  }

  func complete() {
    guard !isCompleted else { return }
    isCompleted = true
    markPersistedChange()
  }

  /// A change to what the split is calculated from, which also needs saving.
  private func markDurableChange() {
    splitCalculationCache = nil
    balanceCache = nil
    durableRevision &+= 1
    markPersistedChange()
  }

  /// A change that needs saving but leaves the split as it was.
  private func markPersistedChange() {
    persistenceRevision &+= 1
  }
}
