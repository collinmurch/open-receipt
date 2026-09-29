import SwiftUI

struct ReceiptRequestsView: View {
  let draft: ReceiptDraft
  let onFlush: () async -> Void
  @State private var people = ReceiptRequestPeople()
  @AppStorage(PaymentSettings.defaultMethodKey) private var defaultPaymentMethodRawValue =
    PaymentSettings.initialDefaultMethod.rawValue
  @Environment(\.contactClient) private var contactClient
  @Environment(\.peopleStorageClient) private var peopleStorage
  @Environment(\.receiptStorageClient) private var receiptStorage

  var body: some View {
    let calculation = draft.splitCalculation
    let ownShare = calculation.participantShares.first { $0.participant.source.isCurrentUser }
    let requestShares = calculation.participantShares.filter {
      !$0.participant.source.isCurrentUser
    }
    let savedPeople = Array(people.peopleByID.values)

    List {
      if let ownShare {
        Section("Your Share") {
          participantLink(
            ownShare,
            person: ReceiptPersonResolver.person(for: ownShare.participant, in: savedPeople),
            calculation: calculation,
            showsPaymentDestination: false)
        }
      }

      if !requestShares.isEmpty {
        Section("Requests") {
          ForEach(requestShares) { share in
            participantLink(
              share,
              person: ReceiptPersonResolver.person(for: share.participant, in: savedPeople),
              calculation: calculation,
              showsPaymentDestination: true)
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
      await people.load(
        receiptStorage: receiptStorage, peopleStorage: peopleStorage, contactClient: contactClient)
    }
    .errorHaptic(people.errorDescription)
    .alert(
      "Couldn’t Update Contact",
      isPresented: Binding(
        get: { people.errorDescription != nil },
        set: { if !$0 { people.errorDescription = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(people.errorDescription ?? "The saved contact could not be updated.")
    }
  }

  private func participantLink(
    _ share: ReceiptParticipantShare,
    person: Person?,
    calculation: ReceiptSplitCalculation,
    showsPaymentDestination: Bool
  ) -> some View {
    NavigationLink {
      ReceiptParticipantBreakdownView(
        share: share,
        person: person,
        currency: draft.displayCurrency,
        adjustmentMethod: draft.adjustmentSplitMethod,
        backgroundStyle: draft.backgroundStyle,
        requestNote: requestNote,
        globalDefault: defaultPaymentMethod,
        isSplitComplete: calculation.unassignedItemCount == 0,
        onRequest: {
          draft.recordRequest(for: share.participant.id, at: $0)
          Task { await onFlush() }
        },
        onSavePerson: savePerson,
        onDeletePerson: deletePerson
      )
    } label: {
      participantRow(
        share,
        person: person,
        showsPaymentDestination: showsPaymentDestination,
        showsTotal: calculation.unassignedItemCount == 0)
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
          let destination = person?.paymentMethods.destination(
            globalDefault: defaultPaymentMethod)
          Text(paymentDestination(destination))
            .font(.caption)
            .foregroundStyle(destination == nil ? .orange : .secondary)
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        if showsTotal {
          Text(share.total, format: .currency(code: draft.displayCurrency))
            .font(.body.monospacedDigit())
            .fontWeight(.semibold)
        } else {
          Text("—")
            .font(.body.monospacedDigit())
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Total unavailable")
        }
        Text(itemDescription(share.items.count))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var requestNote: String {
    let merchant = draft.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    return merchant.isEmpty ? "Receipt split" : "Receipt split: \(merchant)"
  }

  private var defaultPaymentMethod: PaymentMethod {
    PaymentMethod(rawValue: defaultPaymentMethodRawValue)
      ?? PaymentSettings.initialDefaultMethod
  }

  private func paymentDestination(_ destination: PaymentDestination?) -> String {
    guard let destination else {
      return "No payment method set"
    }
    return "\(destination.method.title) \(destination.displayValue)"
  }

  private func itemDescription(_ count: Int) -> String {
    String(AttributedString(localized: "^[\(count) item](inflect: true)").characters)
  }

  private func unassignedDescription(_ calculation: ReceiptSplitCalculation) -> String {
    let count = calculation.unassignedItemCount
    let items = String(
      AttributedString(localized: "^[\(count) unassigned item](inflect: true)").characters)
    let amount = calculation.unassignedItemTotal.formatted(
      .currency(code: draft.displayCurrency))
    return "\(items) totaling \(amount)"
  }

  private func savePerson(_ person: Person) async -> Person? {
    await people.save(person, storage: peopleStorage)
  }

  private func deletePerson(_ person: Person) async -> Bool {
    await people.delete(person, storage: peopleStorage)
  }
}
