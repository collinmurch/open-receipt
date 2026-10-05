import Foundation

/// A two-finger sweep across a receipt's items. Every item from the one the sweep started on
/// through the one under the fingers gets the selected people, or loses them when the first item
/// already had them all. Items the sweep pulls back from return to how they were.
struct ReceiptItemSweep {
  let participantIDs: Set<ReceiptParticipant.ID>
  /// Whether the sweep adds the people to items, rather than removing them.
  let assigns: Bool
  private let itemIDs: [ReceiptDraftItem.ID]
  private let originalAssignments: [ReceiptDraftItem.ID: Set<ReceiptParticipant.ID>]
  private let anchorIndex: Int
  private var currentIndex: Int

  /// Starts a sweep on `itemID`, or returns `nil` without people to assign or an item to start on.
  init?(
    startingAt itemID: ReceiptDraftItem.ID,
    in items: [ReceiptDraftItem],
    participantIDs: Set<ReceiptParticipant.ID>
  ) {
    guard !participantIDs.isEmpty,
      let anchorIndex = items.firstIndex(where: { $0.id == itemID })
    else { return nil }
    self.participantIDs = participantIDs
    assigns = !participantIDs.isSubset(of: items[anchorIndex].participantIDs)
    itemIDs = items.map(\.id)
    originalAssignments = Dictionary(
      items.map { ($0.id, $0.participantIDs) }, uniquingKeysWith: { first, _ in first })
    self.anchorIndex = anchorIndex
    currentIndex = anchorIndex
  }

  /// The items the sweep covers, in receipt order.
  var coveredItemIDs: ArraySlice<ReceiptDraftItem.ID> {
    itemIDs[min(anchorIndex, currentIndex)...max(anchorIndex, currentIndex)]
  }

  /// Moves the sweep's end to `itemID`, returning whether that changed which items it covers.
  mutating func extend(to itemID: ReceiptDraftItem.ID) -> Bool {
    guard let index = itemIDs.firstIndex(of: itemID), index != currentIndex else { return false }
    currentIndex = index
    return true
  }

  /// `items` with the sweep applied: covered items with the people added or removed, and every
  /// other item the sweep started with as it was.
  func applied(to items: [ReceiptDraftItem]) -> [ReceiptDraftItem] {
    let covered = Set(coveredItemIDs)
    return items.map { item in
      guard let original = originalAssignments[item.id] else { return item }
      var item = item
      if covered.contains(item.id) {
        item.participantIDs =
          assigns ? original.union(participantIDs) : original.subtracting(participantIDs)
      } else {
        item.participantIDs = original
      }
      return item
    }
  }
}
