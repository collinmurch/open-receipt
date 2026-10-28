import Foundation
import Observation

@Observable
final class ReceiptDraft {
  let id: UUID
  let backgroundStyle: ReceiptBackgroundStyle
  var merchantName: String { didSet { markPersistedChange() } }
  var date: String { didSet { markPersistedChange() } }
  var subtotal: Money { didSet { markDurableChange() } }
  var adjustments: ReceiptTotalAdjustments {
    didSet {
      if !adjustments.contains(.tip) { tipPercentage = nil }
      markDurableChange()
    }
  }
  var total: Money {
    didSet {
      markDurableChange()
      followTipBase()
    }
  }
  var currency: String {
    didSet {
      markDurableChange()
      followTipBase()
    }
  }
  var payment: ReceiptPayment? { didSet { markPersistedChange() } }
  var items: [ReceiptDraftItem] {
    didSet {
      markDurableChange()
      followTipBase()
    }
  }
  var adjustmentSplitMethod: ReceiptAdjustmentSplitMethod {
    didSet { markDurableChange() }
  }
  /// The order tax, tip, and savings are listed in. The tip is a percentage of the subtotal with
  /// whatever is listed above it. Change it with `setAdjustmentOrder(_:)` so a tip chosen as a
  /// percentage follows its new base.
  var adjustmentOrder: [ReceiptTotalAdjustment] { didSet { markPersistedChange() } }
  /// The percentage of `tipBaseAmount` the tip was chosen as, which it follows as the base
  /// changes. `nil` for a tip entered as an amount or read from the receipt.
  private(set) var tipPercentage: Int? { didSet { markPersistedChange() } }
  private(set) var isCompleted: Bool
  /// The tax and tip still to ask about, in the order they're asked.
  private(set) var unconfirmedAdjustments: [ReceiptTotalAdjustment] {
    didSet { markPersistedChange() }
  }
  private(set) var participants: [ReceiptParticipant]
  /// Counts changes that need saving, so reading it observes the issues and tip placements cached
  /// from them.
  private(set) var persistenceRevision = 0
  /// Counts changes to what the split and balance are worked out from, so reading either
  /// observes them.
  private var durableRevision = 0
  @ObservationIgnored private var splitCalculationCache: ReceiptSplitCalculation?
  @ObservationIgnored private var balanceCache: ReceiptBalance?
  @ObservationIgnored private var issuesCache: [ReceiptIssue]?
  @ObservationIgnored private var tipPlacementCache: [Int: ReceiptBalance.SavingsPlacement] = [:]
  /// The amount being typed into and how the receipt balanced when typing began. Any change
  /// besides typing into it ends the typing.
  @ObservationIgnored var amountEditing: (field: ReceiptAmountField, balance: ReceiptBalance)?

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
    tipPercentage = nil
    isCompleted = false
    unconfirmedAdjustments = []
    participants = [.currentUser(owner: owner)]
  }

  /// Creates a draft from a new recognition of `previous`'s receipt. People, colors, the split
  /// method, the adjustments' order, and an entered tip carry over, the tip as the percentage it
  /// was chosen as; items, printed totals, and assignments are replaced.
  convenience init(receipt: ParsedReceipt, replacing previous: ReceiptDraft) {
    self.init(
      receipt: receipt, id: previous.id, backgroundStyle: previous.backgroundStyle,
      adjustmentSplitMethod: previous.adjustmentSplitMethod,
      adjustmentOrder: previous.adjustmentOrder)
    participants = previous.participants
    guard !adjustments.contains(.tip), let tip = previous.adjustments[.tip] else { return }
    if let percentage = previous.tipPercentage {
      setTipPercentage(percentage)
    } else {
      addAdjustment(.tip, amount: tip)
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
    tipPercentage = state.tipPercentage
    isCompleted = state.isCompleted
    unconfirmedAdjustments = state.unconfirmedAdjustments
    participants = state.participants
    if state.isTipPercentageUnknown { tipPercentage = suggestedTipPercentage }
  }

  /// The tax. Setting it moves a total that added up along with it, as do `tip` and `savings`.
  var tax: Money {
    get { adjustments[.tax] ?? 0 }
    set { keepingBalance(.adjustment(.tax)) { adjustments[.tax] = newValue } }
  }

  /// The tip. Setting it enters it as an amount, which no longer follows a percentage.
  var tip: Money {
    get { adjustments[.tip] ?? 0 }
    set {
      tipPercentage = nil
      keepingBalance(.adjustment(.tip)) { adjustments[.tip] = newValue }
    }
  }

  var savings: Money {
    get { adjustments[.savings] ?? 0 }
    set { keepingBalance(.adjustment(.savings)) { adjustments[.savings] = newValue } }
  }

  /// What needs fixing in the current values. Totals that don't add up aren't an issue, because
  /// the totals section explains them with a `ReceiptBalanceNotice`.
  var issues: [ReceiptIssue] {
    _ = persistenceRevision
    if let issuesCache { return issuesCache }
    let issues = uncachedIssues()
    issuesCache = issues
    return issues
  }

  var splitCalculation: ReceiptSplitCalculation {
    _ = durableRevision
    if let splitCalculationCache { return splitCalculationCache }
    let calculation = ReceiptSplitCalculator.calculate(splitInput, balance: balance)
    splitCalculationCache = calculation
    return calculation
  }

  /// Where savings are read for a tip of `percentage`, worked out with `place` once for each
  /// change to the receipt.
  func tipPlacement(
    for percentage: Int,
    place: () -> ReceiptBalance.SavingsPlacement
  ) -> ReceiptBalance.SavingsPlacement {
    _ = persistenceRevision
    if let cached = tipPlacementCache[percentage] { return cached }
    let placement = place()
    tipPlacementCache[percentage] = placement
    return placement
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
    let merchantName = self.merchantName.trimmed
    if merchantName != self.merchantName { self.merchantName = merchantName }
    let date = self.date.trimmed
    if date != self.date { self.date = date }
    let currency = normalizedCurrency
    if currency != self.currency { self.currency = currency }
    let items = self.items.map { item in
      var item = item
      item.description = item.description.trimmed
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
  func confirm(_ adjustment: ReceiptTotalAdjustment, amount: Money) {
    addAdjustment(adjustment, amount: amount)
    stopAsking(about: adjustment)
  }

  /// Records a tip of `percentage` and stops asking about it.
  func confirmTip(percentage: Int) {
    setTipPercentage(percentage)
    stopAsking(about: .tip)
  }

  /// Stops asking about `adjustment` without recording an amount, for a receipt that has none.
  func stopAsking(about adjustment: ReceiptTotalAdjustment) {
    unconfirmedAdjustments.removeAll { $0 == adjustment }
  }

  /// Chooses the tip as `percentage` of `tipBaseAmount`, adding one if there's none, so it
  /// follows the base from then on. `nil` keeps the tip's amount as an entered one. A total that
  /// added up follows the tip.
  func setTipPercentage(_ percentage: Int?) {
    guard percentage != tipPercentage else { return }
    guard let percentage else {
      tipPercentage = nil
      return
    }
    keepingBalance {
      adjustments.add(.tip)
      tipPercentage = percentage
    }
  }

  /// Starts typing into `field`. Until `endEditing()` or any other change, whether the total
  /// follows each change to it is decided by how the receipt balanced now, so an amount that adds
  /// up partway through typing doesn't move a printed total that didn't.
  func beginEditing(_ field: ReceiptAmountField) {
    amountEditing = (field, balance)
  }

  func endEditing() {
    amountEditing = nil
  }

  func complete() {
    guard !isCompleted else { return }
    isCompleted = true
    markPersistedChange()
  }

  /// A change to what the split is calculated from, which also needs saving.
  private func markDurableChange() {
    amountEditing = nil
    splitCalculationCache = nil
    balanceCache = nil
    durableRevision &+= 1
    markPersistedChange()
  }

  /// A change that needs saving but leaves the split as it was.
  private func markPersistedChange() {
    issuesCache = nil
    tipPlacementCache = [:]
    persistenceRevision &+= 1
  }
}
