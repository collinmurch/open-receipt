import SwiftUI

/// One person's share on a card, filled like a list row, with what to do about it below.
/// Tapping the person opens their contact, when they have one.
struct ReceiptShareCard<Accessory: View, Actions: View>: View {
  let share: ReceiptParticipantShare
  let paymentDestination: PaymentDestination?
  /// The share's chosen payment method, when nothing says where it sends requests.
  let blankPaymentMethod: PaymentMethod?
  /// Whether to caption where requests go, which the owner's own share leaves out.
  let showsPaymentDestination: Bool
  let showsTotal: Bool
  let currency: String
  let onOpenContact: (() -> Void)?
  /// Drawn after the share's total.
  @ViewBuilder let accessory: Accessory
  @ViewBuilder let actions: Actions
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    // Accessibility sizes stack the total under the person, giving each the card's full width.
    let isStacked = dynamicTypeSize.isAccessibilitySize
    let layout =
      isStacked
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
      : AnyLayout(HStackLayout(spacing: 12))
    VStack(spacing: 20) {
      layout {
        if let onOpenContact {
          Button(action: onOpenContact) {
            identity
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityElement(children: .combine)
          .accessibilityHint("Show this person’s contact")
        } else {
          identity
            .accessibilityElement(children: .combine)
        }

        HStack(spacing: 12) {
          VStack(alignment: isStacked ? .leading : .trailing, spacing: 2) {
            ShareTotalText(amount: showsTotal ? share.total : nil, currency: currency)
            Text(share.itemCountText)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          if isStacked {
            Spacer(minLength: 0)
          }
          accessory
        }
      }

      actions
    }
    .padding(14)
    .frame(maxWidth: .infinity)
    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
  }

  private var identity: some View {
    HStack(spacing: 12) {
      ContactAvatarView(
        name: share.participant.displayName,
        contactIdentifier: share.participant.source.contactIdentifier)
      VStack(alignment: .leading, spacing: 2) {
        Text(share.participant.displayName)
        if showsPaymentDestination {
          PaymentDestinationCaption(
            destination: paymentDestination, blankMethod: blankPaymentMethod)
        }
      }
      Spacer(minLength: 0)
    }
  }
}

/// A share's payment request.
struct ShareRequestButton: View {
  let request: PreparedPaymentRequest
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ShareCardButtonLabel(title: request.title, systemImage: request.systemImage)
        .foregroundStyle(.white)
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.tint(request.method.prominentColor).interactive(), in: .capsule)
  }
}

/// Opens one person's breakdown full screen, where it can be shared.
struct ViewBreakdownButton: View {
  let sourceID: AnyHashable
  let transition: Namespace.ID
  let action: () -> Void
  @ScaledMetric(relativeTo: .body) private var size: CGFloat = 46

  var body: some View {
    Button(action: action) {
      Image(systemName: "receipt")
        .font(.body.weight(.semibold))
        .frame(width: size, height: size)
        .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.interactive(), in: .circle)
    .matchedTransitionSource(id: sourceID, in: transition)
    .accessibilityLabel("View Breakdown")
  }
}

/// A share card button's title and symbol, sized to the title.
struct ShareCardButtonLabel: View {
  let title: String
  let systemImage: String
  @ScaledMetric(relativeTo: .body) private var height: CGFloat = 46

  var body: some View {
    HStack(spacing: 8) {
      Text(title)
        .buttonTitleLineLimit()
        .minimumScaleFactor(0.8)
      Image(systemName: systemImage)
    }
    .font(.body.weight(.semibold))
    .padding(.horizontal, 16)
    .frame(minHeight: height)
    .contentShape(.capsule)
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

/// Where a person's payment requests go, or a warning when they have no payment method or
/// their chosen one is blank.
struct PaymentDestinationCaption: View {
  let destination: PaymentDestination?
  let blankMethod: PaymentMethod?

  var body: some View {
    if let destination {
      Text("\(destination.method.title) \(destination.displayValue)")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      Text(blankMethod?.blankMessage ?? "No payment method set")
        .font(.caption)
        .foregroundStyle(.orange)
    }
  }
}
