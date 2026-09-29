import SwiftUI

struct ReceiptItemsSection: View {
  let draft: ReceiptDraft
  let isEditing: Bool
  @Binding var selectedParticipantIDs: Set<ReceiptParticipant.ID>
  let displayCurrency: String
  @Binding var haptic: HapticEvent
  let onSelectItem: (ReceiptDraftItem.ID) -> Void

  var body: some View {
    Section {
      ForEach(draft.items) { item in
        ReceiptItemRow(
          item: item,
          assignedParticipants: isEditing ? [] : draft.participants(assignedTo: item),
          isAssignedToSelection: isAssignedToSelection(item),
          hasSelection: !selectedParticipantIDs.isEmpty,
          isEditing: isEditing,
          displayCurrency: displayCurrency,
          onTap: { tap(item.id) }
        )
        .equatable()
      }
      .onDelete { offsets in
        draft.removeItems(at: offsets)
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
      .animation(.smooth(duration: 0.35), value: isEditing)
    }
  }

  private func tap(_ id: ReceiptDraftItem.ID) {
    guard let item = draft.items.first(where: { $0.id == id }) else { return }
    if isEditing {
      onSelectItem(id)
      return
    }
    if selectedParticipantIDs.isEmpty {
      guard !item.participantIDs.isEmpty else { return }
      withAnimation(.smooth(duration: 0.25)) {
        selectedParticipantIDs = item.participantIDs
      }
    } else {
      withAnimation(.smooth(duration: 0.25)) {
        draft.toggleAssignment(of: selectedParticipantIDs, to: id)
      }
    }
    haptic.play(.selection)
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
  let displayCurrency: String
  let onTap: () -> Void

  nonisolated static func == (lhs: ReceiptItemRow, rhs: ReceiptItemRow) -> Bool {
    lhs.item == rhs.item
      && lhs.assignedParticipants == rhs.assignedParticipants
      && lhs.isAssignedToSelection == rhs.isAssignedToSelection
      && lhs.hasSelection == rhs.hasSelection
      && lhs.isEditing == rhs.isEditing
      && lhs.displayCurrency == rhs.displayCurrency
  }

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
    .contentShape(.rect)
    .onTapGesture(perform: onTap)
    .accessibilityAddTraits(.isButton)
    .accessibilityHint(accessibilityHint)
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

  private var accessibilityHint: String {
    if isEditing { return "Edit this item" }
    if !hasSelection {
      return item.participantIDs.isEmpty
        ? "Select one or more people before assigning this item"
        : "Select the people assigned to this item"
    }
    return isAssignedToSelection
      ? "Remove the selected people from this item"
      : "Assign the selected people to this item"
  }
}
