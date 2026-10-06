import SwiftUI

struct ParticipantStrip: View {
  /// The strip's height at the default text size. Views that inset content below the strip scale
  /// it with `@ScaledMetric(relativeTo: .caption2)`.
  static let baseHeight: CGFloat = 94

  let participants: [ReceiptParticipant]
  let amountsOwed: [ReceiptParticipant.ID: Double]
  let currency: String
  let selectedParticipantIDs: Set<ReceiptParticipant.ID>
  let onSelect: (ReceiptParticipant.ID) -> Void
  let onManagePeople: () -> Void
  /// Clears the selection from a button beside the strip, shown while anyone is selected.
  let onClearSelection: () -> Void
  /// Where the people sheet zooms from when the Add button opens it.
  var addTransition: (id: AnyHashable, namespace: Namespace.ID)?

  @ScaledMetric(relativeTo: .caption2) private var height = Self.baseHeight
  @ScaledMetric(relativeTo: .caption2) private var avatarSize: CGFloat = 38
  @ScaledMetric(relativeTo: .caption2) private var itemWidth: CGFloat = 58
  @ScaledMetric(relativeTo: .caption2) private var spacing: CGFloat = 14
  @ScaledMetric(relativeTo: .caption2) private var clearButtonWidth: CGFloat = 52
  private let cornerRadius: CGFloat = 22
  private let horizontalPadding: CGFloat = 14
  private let clearButtonSpacing: CGFloat = 8

  var body: some View {
    let shortNames = ParticipantShortNames.names(for: participants)
    GeometryReader { proxy in
      let stripWidth = min(idealWidth, stripAvailableWidth(in: proxy.size.width))
      GlassEffectContainer(spacing: clearButtonSpacing) {
        strip(shortNames: shortNames)
          .frame(width: stripWidth, alignment: .leading)
          .glassEffect(in: .rect(cornerRadius: cornerRadius))
          .screenshotHighlight("receipt-participants")
          .overlay(alignment: .trailing) { clearButton }
          // Centers the strip and its clear button together.
          .offset(x: showsClearButton ? -clearButtonReach / 2 : 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(height: height)
  }

  private func strip(shortNames: [ReceiptParticipant.ID: String]) -> some View {
    ScrollView(.horizontal) {
      HStack(spacing: spacing) {
        ForEach(participants) { participant in
          participantButton(
            participant, shortName: shortNames[participant.id] ?? participant.displayName)
        }

        Button(action: onManagePeople) {
          VStack(spacing: 4) {
            addSymbol
            Text("Add")
              .font(.caption2)
          }
          .frame(width: itemWidth)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add people")
      }
      .padding(.horizontal, horizontalPadding)
      .frame(maxHeight: .infinity)
      // Only the avatars' selection marks take this pace. The glass and clear button follow the
      // change that moved them, so they travel with a lifted focus instead of racing it.
      .animation(.selectionChange, value: selectedParticipantIDs)
    }
    .scrollIndicators(.hidden)
  }

  /// The clear button always stays in the glass, tucked under the strip's trailing edge until
  /// there's a selection, so it slides out of the strip, and back in, with whatever moves the strip.
  private var clearButton: some View {
    Button("Clear Selection", systemImage: "person.2.slash", action: onClearSelection)
      .labelStyle(.iconOnly)
      .font(.headline)
      .frame(width: clearButtonWidth)
      .frame(maxHeight: .infinity)
      .contentShape(.rect)
      .opacity(showsClearButton ? 1 : 0)
      .buttonStyle(.plain)
      .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
      .offset(x: showsClearButton ? clearButtonReach : 0)
      .allowsHitTesting(showsClearButton)
      .accessibilityHidden(!showsClearButton)
  }

  private var clearButtonReach: CGFloat { clearButtonWidth + clearButtonSpacing }

  private var showsClearButton: Bool { !selectedParticipantIDs.isEmpty }

  private func stripAvailableWidth(in width: CGFloat) -> CGFloat {
    showsClearButton ? width - clearButtonReach : width
  }

  private func participantButton(_ participant: ReceiptParticipant, shortName: String)
    -> some View
  {
    let isSelected = selectedParticipantIDs.contains(participant.id)
    let amount = amountsOwed[participant.id, default: 0]
    return Button {
      onSelect(participant.id)
    } label: {
      VStack(spacing: 4) {
        PersonAvatarView(
          name: participant.displayName,
          imageData: participant.avatarData,
          size: avatarSize
        )
        .overlay {
          if isSelected {
            Circle()
              .stroke(.tint, lineWidth: 3)
          }
        }
        .overlay(alignment: .bottomTrailing) {
          if isSelected {
            Image(systemName: "checkmark.circle.fill")
              .font(.caption.weight(.bold))
              .foregroundStyle(.white, .tint)
              .background(.background, in: .circle)
              .transition(.scale.combined(with: .opacity))
          }
        }
        Text(shortName)
          .font(.caption2)
          .lineLimit(1)
        Text(amount, format: .currency(code: currency))
          .font(.caption2.monospacedDigit().weight(.semibold))
          .foregroundStyle(.tint)
          .contentTransition(.numericText(value: amount))
      }
      .frame(width: itemWidth)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(participant.displayName)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityHint("Select this person for item assignment")
  }

  @ViewBuilder
  private var addSymbol: some View {
    let symbol = Image(systemName: "plus")
      .font(.headline)
      .frame(width: avatarSize, height: avatarSize)
      .background(.secondary.opacity(0.16), in: .circle)
    if let addTransition {
      symbol.matchedTransitionSource(id: addTransition.id, in: addTransition.namespace)
    } else {
      symbol
    }
  }

  private var idealWidth: CGFloat {
    let itemCount = CGFloat(participants.count + 1)
    return (itemCount * itemWidth) + ((itemCount - 1) * spacing) + (horizontalPadding * 2)
  }
}
