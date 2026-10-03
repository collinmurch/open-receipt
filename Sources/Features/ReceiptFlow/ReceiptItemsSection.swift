import SwiftUI

struct ReceiptItemsSection: View {
  let draft: ReceiptDraft
  let isEditing: Bool
  @Binding var selectedParticipantIDs: Set<ReceiptParticipant.ID>
  /// The item whose people were copied into the selection, until anything else changes it.
  @Binding var seededItemID: ReceiptDraftItem.ID?
  @Binding var haptic: HapticEvent
  /// The item lifted into focus, and whether its focused copy is on screen yet.
  let focusedItemID: ReceiptDraftItem.ID?
  let isFocusPresented: Bool
  let onSelectItem: (ReceiptDraftItem.ID) -> Void
  /// Focuses an item, noting whether it was pressed into focus and so is already bulging.
  let onFocusItem: (_ id: ReceiptDraftItem.ID, _ isPressed: Bool) -> Void
  let onFocusedRowFrameChange: (CGRect) -> Void

  var body: some View {
    let displayCurrency = draft.displayCurrency
    Section {
      ForEach(draft.items) { item in
        ReceiptItemRow(
          item: item,
          assignedParticipants: isEditing ? [] : draft.participants(assignedTo: item),
          isAssignedToSelection: isAssignedToSelection(item),
          hasSelection: !selectedParticipantIDs.isEmpty,
          isEditing: isEditing,
          isFocused: item.id == focusedItemID,
          isLiftedOut: item.id == focusedItemID && isFocusPresented,
          displayCurrency: displayCurrency,
          onTap: { tap(item.id) },
          onFocus: { focus(item.id, isPressed: $0) },
          onFocusedFrameChange: onFocusedRowFrameChange
        )
        .equatable()
      }
      .onDelete { offsets in
        draft.items.remove(atOffsets: offsets)
        haptic.play(.removal)
      }
      .deleteDisabled(!isEditing)
    } header: {
      Text("Items")
    } footer: {
      HStack {
        Spacer()
        Button("Add Item", systemImage: "plus") {
          onSelectItem(draft.addItem())
        }
        .buttonStyle(.bordered)
        Spacer()
      }
      .frame(height: isEditing ? 48 : 0)
      .opacity(isEditing ? 1 : 0)
      .clipped()
      .allowsHitTesting(isEditing)
      .padding(.top, isEditing ? 4 : 0)
      .animation(.settle, value: isEditing)
    }
  }

  private func tap(_ id: ReceiptDraftItem.ID) {
    guard let item = draft.items.first(where: { $0.id == id }) else { return }
    if isEditing {
      onSelectItem(id)
      return
    }
    if selectedParticipantIDs.isEmpty {
      guard !item.participantIDs.isEmpty else {
        onFocusItem(id, false)
        return
      }
      withAnimation(.selectionChange) {
        selectedParticipantIDs = item.participantIDs
      }
      seededItemID = id
    } else if seededItemID == id {
      // Tapping the item again undoes copying its people rather than unassigning all of them.
      withAnimation(.selectionChange) {
        selectedParticipantIDs = []
      }
      seededItemID = nil
    } else {
      withAnimation(.selectionChange) {
        draft.toggleAssignment(of: selectedParticipantIDs, to: id)
      }
      seededItemID = nil
    }
    haptic.play(.selection)
  }

  private func focus(_ id: ReceiptDraftItem.ID, isPressed: Bool) {
    guard !isEditing, focusedItemID == nil else { return }
    onFocusItem(id, isPressed)
  }

  private func isAssignedToSelection(_ item: ReceiptDraftItem) -> Bool {
    !selectedParticipantIDs.isEmpty && selectedParticipantIDs.isSubset(of: item.participantIDs)
  }
}

/// One receipt item. Its inputs are plain values, so a change to one item redraws only that row.
private struct ReceiptItemRow: View, Equatable {
  let item: ReceiptDraftItem
  let assignedParticipants: [ReceiptParticipant]
  let isAssignedToSelection: Bool
  let hasSelection: Bool
  let isEditing: Bool
  let isFocused: Bool
  let isLiftedOut: Bool
  let displayCurrency: String
  let onTap: () -> Void
  let onFocus: (_ isPressed: Bool) -> Void
  let onFocusedFrameChange: (CGRect) -> Void

  @State private var isPressed = false

  nonisolated static func == (lhs: ReceiptItemRow, rhs: ReceiptItemRow) -> Bool {
    lhs.item == rhs.item
      && lhs.assignedParticipants == rhs.assignedParticipants
      && lhs.isAssignedToSelection == rhs.isAssignedToSelection
      && lhs.hasSelection == rhs.hasSelection
      && lhs.isEditing == rhs.isEditing
      && lhs.isFocused == rhs.isFocused
      && lhs.isLiftedOut == rhs.isLiftedOut
      && lhs.displayCurrency == rhs.displayCurrency
  }

  /// Taps and long presses are one gesture rather than a `Button`: a list row's button takes its
  /// taps from the row's selection, which cancels any long press attached to it.
  var body: some View {
    ReceiptItemRowContent(
      item: item,
      assignedParticipants: assignedParticipants,
      isAssignedToSelection: isAssignedToSelection,
      isEditing: isEditing,
      displayCurrency: displayCurrency
    )
    .onGeometryChange(for: CGRect?.self) { proxy in
      isFocused ? proxy.frame(in: .global) : nil
    } action: { frame in
      if let frame { onFocusedFrameChange(frame) }
    }
    .pressScale(isPressed)
    // The focused copy stands in for the row, so the row hides and returns in one frame.
    .opacity(isLiftedOut ? 0 : 1)
    .transaction(value: isLiftedOut) { $0.animation = nil }
    .contentShape(.rect)
    .gesture(
      ReceiptRowPressGesture(
        onPressingChanged: { isPressed = $0 },
        onTap: onTap,
        onLongPress: { onFocus(true) }
      )
    )
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(.default, onTap)
    .accessibilityHint(accessibilityHint)
    .accessibilityActions {
      if !isEditing {
        Button("Assign People") { onFocus(false) }
      }
    }
  }

  private var accessibilityHint: String {
    if isEditing { return "Edit this item" }
    if !hasSelection {
      return item.participantIDs.isEmpty
        ? "Choose the people who shared this item"
        : "Select the people assigned to this item"
    }
    return isAssignedToSelection
      ? "Remove the selected people from this item"
      : "Assign the selected people to this item"
  }
}

/// What a receipt item row draws, shared by the list and the item lifted into focus.
struct ReceiptItemRowContent: View {
  /// How much a row grows while pressed, and stays grown while lifted into focus.
  static let pressedScale: CGFloat = 1.03

  let item: ReceiptDraftItem
  let assignedParticipants: [ReceiptParticipant]
  let isAssignedToSelection: Bool
  let isEditing: Bool
  let displayCurrency: String

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        VStack(alignment: .leading) {
          Text(item.description.isEmpty ? "New Item" : item.description)
          if item.quantity != 1 {
            Text("Quantity \(item.quantity, format: .number)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Text(item.lineTotal, format: .currency(code: displayCurrency))
          .font(.body.monospacedDigit())
          .contentTransition(.numericText(value: item.lineTotal))

        if isEditing {
          Image(systemName: "chevron.forward")
            .font(.body.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 10, alignment: .trailing)
        }
      }

      if !isEditing {
        HStack {
          assignments
          Spacer()
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.tint)
            .symbolEffect(.bounce, value: isAssignedToSelection)
            .opacity(isAssignedToSelection ? 1 : 0)
            .frame(width: 20, alignment: .trailing)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
  }

  @ViewBuilder
  private var assignments: some View {
    if assignedParticipants.isEmpty {
      Text("Unassigned")
        .font(.caption)
        .foregroundStyle(.orange)
    } else {
      HStack(spacing: -5) {
        ForEach(assignedParticipants) { participant in
          PersonAvatarView(
            name: participant.displayName,
            imageData: participant.avatarData,
            size: 25
          )
          .overlay(Circle().stroke(.background, lineWidth: 2))
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "Assigned to \(assignedParticipants.map(\.displayName).formatted())")
    }
  }
}
