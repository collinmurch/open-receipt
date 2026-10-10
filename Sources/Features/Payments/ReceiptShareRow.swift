import SwiftUI

/// One person's share in the list. Taps open the breakdown and long presses lift the share out to
/// request or send it, as receipt items do.
struct ReceiptShareRow: View {
  let content: ReceiptShareRowContent
  let isFocused: Bool
  let isLiftedOut: Bool
  let onTap: () -> Void
  let onFocus: (_ isPressed: Bool) -> Void
  let onFocusedFrameChange: (CGRect) -> Void

  var body: some View {
    HStack(spacing: 12) {
      content
      Image(systemName: "chevron.forward")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .liftableRow(
      isFocused: isFocused,
      isLiftedOut: isLiftedOut,
      onTap: onTap,
      onLongPress: { onFocus(true) },
      onFocusedFrameChange: onFocusedFrameChange
    )
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(.default, onTap)
    .accessibilityHint("Show this person’s breakdown")
    .accessibilityActions {
      Button("Request or Share Individual Breakdown") { onFocus(false) }
    }
  }
}

/// What a share row draws, shared by the list and the share lifted into focus.
struct ReceiptShareRowContent: View {
  let share: ReceiptParticipantShare
  let paymentDestination: PaymentDestination?
  /// Whether to caption where requests go, which the owner's own share leaves out.
  let showsPaymentDestination: Bool
  let showsTotal: Bool
  let currency: String

  var body: some View {
    HStack(spacing: 12) {
      ContactAvatarView(
        name: share.participant.displayName,
        contactIdentifier: share.participant.source.contactIdentifier)
      VStack(alignment: .leading, spacing: 2) {
        Text(share.participant.displayName)
        if showsPaymentDestination {
          PaymentDestinationCaption(destination: paymentDestination)
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        ShareTotalText(amount: showsTotal ? share.total : nil, currency: currency)
        Text(share.itemCountText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// A person's share, or a dash while unassigned items keep the share from being final.
struct ShareTotalText: View {
  let amount: Double?
  let currency: String

  var body: some View {
    Group {
      if let amount {
        Text(amount, format: .currency(code: currency))
      } else {
        Text("—")
          .foregroundStyle(.secondary)
          .accessibilityLabel("Total unavailable")
      }
    }
    .font(.body.monospacedDigit())
    .fontWeight(.semibold)
  }
}

/// Where a person's payment requests go, or a warning when they have no payment method.
struct PaymentDestinationCaption: View {
  let destination: PaymentDestination?

  var body: some View {
    if let destination {
      Text("\(destination.method.title) \(destination.displayValue)")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      Text("No payment method set")
        .font(.caption)
        .foregroundStyle(.orange)
    }
  }
}
