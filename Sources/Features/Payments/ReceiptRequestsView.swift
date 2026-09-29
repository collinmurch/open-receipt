import SwiftUI

struct ReceiptRequestsView: View {
  let draft: ReceiptDraft
  let onFlush: () async -> Void
  @State private var people: SavedPeopleModel
  @State private var hasLoadedPeople = false
  @AppStorage(PaymentSettings.defaultMethodKey) private var defaultPaymentMethod =
    PaymentSettings.initialDefaultMethod
  @Environment(\.contactClient) private var contactClient

  init(draft: ReceiptDraft, peopleStorage: PeopleStorageClient, onFlush: @escaping () async -> Void)
  {
    self.draft = draft
    self.onFlush = onFlush
    _people = State(initialValue: SavedPeopleModel(storage: peopleStorage))
  }

  var body: some View {
    let calculation = draft.splitCalculation
    let ownShare = calculation.participantShares.first { $0.participant.source.isCurrentUser }
    let requestShares = calculation.participantShares.filter {
      !$0.participant.source.isCurrentUser
    }

    List {
      if let ownShare {
        Section("Your Share") {
          participantLink(ownShare, calculation: calculation, showsPaymentDestination: false)
        }
      }

      if !requestShares.isEmpty {
        Section("Requests") {
          ForEach(requestShares) { share in
            participantLink(share, calculation: calculation, showsPaymentDestination: true)
          }
        }
      }

      if calculation.unassignedItemCount > 0 {
        Section {
          Label(
            "Assign \(unassignedDescription(calculation)) before you send requests.",
            systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(.orange)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .task {
      guard !hasLoadedPeople else { return }
      await people.load()
      await people.adoptContactPaymentDefaults(from: contactClient)
      hasLoadedPeople = people.errorDescription == nil
    }
    .errorAlert("Couldn’t Update Contact", message: $people.errorDescription)
  }

  private func participantLink(
    _ share: ReceiptParticipantShare,
    calculation: ReceiptSplitCalculation,
    showsPaymentDestination: Bool
  ) -> some View {
    let person = ReceiptPersonResolver.person(for: share.participant, in: people.people)
    let isSplitComplete = calculation.unassignedItemCount == 0
    return NavigationLink {
      ReceiptParticipantBreakdownView(
        share: share,
        person: person,
        currency: draft.displayCurrency,
        adjustmentMethod: draft.adjustmentSplitMethod,
        backgroundStyle: draft.backgroundStyle,
        requestNote: requestNote,
        globalDefault: defaultPaymentMethod,
        isSplitComplete: isSplitComplete,
        onRequest: {
          draft.recordRequest(for: share.participant.id, at: $0)
          Task { await onFlush() }
        },
        onSavePerson: { await people.save($0) },
        onDeletePerson: { await people.delete($0) }
      )
    } label: {
      participantRow(
        share,
        person: person,
        showsPaymentDestination: showsPaymentDestination,
        showsTotal: isSplitComplete)
    }
    .screenshotHighlight("request-\(share.participant.displayName)")
  }

  private func participantRow(
    _ share: ReceiptParticipantShare,
    person: Person?,
    showsPaymentDestination: Bool,
    showsTotal: Bool
  ) -> some View {
    HStack(spacing: 12) {
      PersonAvatarView(
        name: share.participant.displayName,
        imageData: share.participant.avatarData)
      VStack(alignment: .leading, spacing: 2) {
        Text(share.participant.displayName)
        if showsPaymentDestination {
          PaymentDestinationCaption(
            destination: person?.paymentMethods.destination(globalDefault: defaultPaymentMethod))
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        ShareTotalText(amount: showsTotal ? share.total : nil, currency: draft.displayCurrency)
        Text(String(inflecting: "^[\(share.items.count) item](inflect: true)"))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var requestNote: String {
    let merchant = draft.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    return merchant.isEmpty ? "Receipt split" : "Receipt split: \(merchant)"
  }

  private func unassignedDescription(_ calculation: ReceiptSplitCalculation) -> String {
    let count = calculation.unassignedItemCount
    let items = String(inflecting: "^[\(count) unassigned item](inflect: true)")
    let amount = calculation.unassignedItemTotal.formatted(
      .currency(code: draft.displayCurrency))
    return "\(items) totaling \(amount)"
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
