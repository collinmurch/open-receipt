import MessageUI
import SwiftUI

struct ReceiptRequestsView: View {
  let draft: ReceiptDraft
  let adjustmentMethod: ReceiptAdjustmentSplitMethod
  let onFlush: () async -> Void
  @State private var peopleByID: [Person.ID: Person] = [:]
  @State private var peopleErrorDescription: String?
  @State private var hasLoadedPeople = false
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

    List {
      if let ownShare {
        Section("Your Share") {
          participantLink(
            ownShare,
            calculation: calculation,
            showsPaymentDestination: false)
        }
      }

      if !requestShares.isEmpty {
        Section("Requests") {
          ForEach(requestShares) { share in
            participantLink(
              share,
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
    .receiptBackground(draft.backgroundStyle)
    .task { await loadPeople() }
    .errorHaptic(peopleErrorDescription)
    .alert(
      "Couldn’t Update Contact",
      isPresented: Binding(
        get: { peopleErrorDescription != nil },
        set: { if !$0 { peopleErrorDescription = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(peopleErrorDescription ?? "The saved contact could not be updated.")
    }
  }

  private func participantLink(
    _ share: ReceiptParticipantShare,
    calculation: ReceiptSplitCalculation,
    showsPaymentDestination: Bool
  ) -> some View {
    let person = ReceiptPersonResolver.person(
      for: share.participant,
      in: Array(peopleByID.values))
    return NavigationLink {
      ReceiptParticipantBreakdownView(
        share: share,
        person: person,
        currency: displayCurrency,
        adjustmentMethod: adjustmentMethod,
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
          Text(share.total, format: .currency(code: displayCurrency))
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

  private var displayCurrency: String {
    let currency = draft.normalizedCurrency
    return currency.count == 3 ? currency : "USD"
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
      .currency(code: displayCurrency))
    return "\(items) totaling \(amount)"
  }

  private func loadPeople() async {
    guard !hasLoadedPeople else { return }
    do {
      let snapshots = try await receiptStorage.listPersonSnapshots()
      try Task.checkCancellation()
      try await peopleStorage.importReceiptParticipants(snapshots)
      try Task.checkCancellation()
      var people = try await peopleStorage.list()
      try Task.checkCancellation()
      let defaults = await contactClient.defaultPaymentMethods(for: people)
      for index in people.indices {
        try Task.checkCancellation()
        guard let paymentDefaults = defaults[people[index].id] else { continue }
        var didChange = false
        if let recipient = paymentDefaults.venmo {
          people[index].paymentMethods.venmo = .init(recipient: recipient)
          didChange = true
        }
        if let recipient = paymentDefaults.iMessage {
          people[index].paymentMethods.iMessage = .init(recipient: recipient)
          didChange = true
        }
        if didChange {
          people[index] = try await peopleStorage.save(people[index])
        }
      }
      try Task.checkCancellation()
      peopleByID = Dictionary(
        uniqueKeysWithValues: people.map {
          ($0.id, $0)
        })
      hasLoadedPeople = true
    } catch is CancellationError {
      return
    } catch {
      peopleErrorDescription = error.localizedDescription
    }
  }

  private func savePerson(_ person: Person) async -> Person? {
    do {
      let saved = try await peopleStorage.save(person)
      peopleByID[saved.id] = saved
      peopleErrorDescription = nil
      return saved
    } catch {
      peopleErrorDescription = error.localizedDescription
      return nil
    }
  }

  private func deletePerson(_ person: Person) async -> Bool {
    do {
      try await peopleStorage.delete(person.id)
      peopleByID[person.id] = nil
      peopleErrorDescription = nil
      return true
    } catch {
      peopleErrorDescription = error.localizedDescription
      return false
    }
  }
}

private struct ReceiptParticipantBreakdownView: View {
  let share: ReceiptParticipantShare
  let person: Person?
  let currency: String
  let adjustmentMethod: ReceiptAdjustmentSplitMethod
  let backgroundStyle: ReceiptBackgroundStyle
  let requestNote: String
  let globalDefault: PaymentMethod
  let isSplitComplete: Bool
  let onRequest: (Date) -> Void
  let onSavePerson: (Person) async -> Person?
  let onDeletePerson: (Person) async -> Bool
  @State private var selectedPerson: Person?
  @State private var requestErrorDescription: String?
  @State private var messageComposition: IMessageComposition?
  @State private var requestedAt: Date?
  @State private var haptic = HapticEvent()
  @ScaledMetric(relativeTo: .body) private var requestButtonHeight: CGFloat = 50
  @Environment(\.openURL) private var openURL
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    List {
      Section("Payment") {
        LabeledContent("Amount Due") {
          totalValue
        }

        if !share.participant.source.isCurrentUser {
          if let person {
            Button {
              selectedPerson = person
            } label: {
              HStack(spacing: 12) {
                paymentDestinationRow
                Image(systemName: "chevron.right")
                  .font(.footnote.weight(.semibold))
                  .foregroundStyle(.tertiary)
              }
            }
            .tint(.primary)
            .accessibilityHint("Edit payment methods")
          } else {
            paymentDestinationRow
          }
        }
      }

      Section("Items") {
        if share.items.isEmpty {
          Text("No assigned items")
            .foregroundStyle(.secondary)
        } else {
          ForEach(share.items) { item in
            breakdownRow(
              title: item.description,
              subtitle: item.fraction < 1
                ? "\(formattedPercentage(item.fraction)) share" : nil,
              amount: item.amount)
          }
        }
      }

      if !share.adjustments.isEmpty {
        Section {
          ForEach(share.adjustments) { adjustment in
            breakdownRow(
              title: adjustment.title,
              subtitle: formattedPercentage(adjustment.fraction),
              amount: adjustment.amount)
          }
        } header: {
          Text("Adjustments")
        } footer: {
          Text(
            adjustmentMethod == .proportional
              ? "Based on this person’s item share."
              : "Adjustments are divided equally among all people."
          )
        }
      }

      Section {
        HStack {
          Text("Total")
            .fontWeight(.semibold)
          Spacer()
          totalValue
        }
      }

      if let paymentDestination, currency != "USD" {
        Section {
          Label(
            "\(paymentDestination.method.title) requests require a USD receipt.",
            systemImage: "dollarsign.circle"
          )
          .foregroundStyle(.secondary)
        }
      }
    }
    .contentMargins(.bottom, requestButtonBottomMargin, for: .scrollContent)
    .receiptBackground(backgroundStyle)
    .navigationTitle(share.participant.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarVisibility(.hidden, for: .tabBar)
    .toolbar {
      ToolbarItem(placement: .principal) {
        VStack(spacing: 0) {
          Text(share.participant.displayName)
            .font(.headline)
          if !share.participant.source.isCurrentUser, paymentDestination == nil {
            Text("No payment method set")
              .font(.caption2)
              .foregroundStyle(.orange)
          }
        }
      }

      if person != nil, !share.participant.source.isCurrentUser {
        ToolbarItem(placement: .topBarTrailing) {
          Button("View Contact", systemImage: "person.crop.circle") {
            selectedPerson = person
          }
          .labelStyle(.iconOnly)
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if let preparedRequest {
        VStack(spacing: 4) {
          Button {
            open(preparedRequest)
          } label: {
            HStack(spacing: 10) {
              Text(requestButtonTitle(for: preparedRequest.method))
              Image(systemName: requestButtonImage(for: preparedRequest.method))
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, 18)
            .frame(minHeight: requestButtonHeight)
            .contentShape(.capsule)
          }
          .buttonStyle(.plain)
          .foregroundStyle(preparedRequest.method.color(for: colorScheme))
          .glassEffect(.regular.interactive(), in: .capsule)

          if let lastRequestedAt {
            Text("Last requested \(PaymentRequestDateFormatter.formatted(lastRequestedAt))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.bottom, 8)
      }
    }
    .haptics(haptic)
    .errorHaptic(requestErrorDescription)
    .sheet(item: $messageComposition) { composition in
      IMessageComposerView(composition: composition) { sent in
        messageComposition = nil
        if sent {
          recordRequest()
          haptic.play(.success)
        }
      }
    }
    .sheet(item: $selectedPerson) { selectedPerson in
      NavigationStack {
        PersonDetailView(
          person: selectedPerson,
          onSave: onSavePerson,
          onDelete: onDeletePerson
        )
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Close", systemImage: "xmark") {
              self.selectedPerson = nil
            }
            .labelStyle(.iconOnly)
          }
        }
      }
    }
    .alert(
      "Couldn’t Open Payment Request",
      isPresented: Binding(
        get: { requestErrorDescription != nil },
        set: { if !$0 { requestErrorDescription = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(requestErrorDescription ?? "The payment request could not open.")
    }
  }

  @ViewBuilder
  private var paymentDestinationRow: some View {
    if let paymentDestination {
      LabeledContent(
        paymentDestination.method.title,
        value: paymentDestination.displayValue)
    } else {
      LabeledContent("Payment Method") {
        Text("Not set")
          .foregroundStyle(.orange)
      }
    }
  }

  @ViewBuilder
  private var totalValue: some View {
    if isSplitComplete {
      Text(share.total, format: .currency(code: currency))
        .font(.body.monospacedDigit())
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
    } else {
      Text("—")
        .font(.body.monospacedDigit())
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Total unavailable")
    }
  }

  private var paymentDestination: PaymentDestination? {
    person?.paymentMethods.destination(globalDefault: globalDefault)
  }

  private var preparedRequest: PreparedPaymentRequest? {
    guard isSplitComplete,
      currency == "USD",
      !share.participant.source.isCurrentUser,
      let paymentDestination
    else { return nil }

    switch paymentDestination {
    case .venmo(let recipient):
      guard
        let url = VenmoRequestURL.make(
          recipient: recipient,
          amount: share.total,
          note: requestNote)
      else { return nil }
      return PreparedPaymentRequest(method: .venmo, action: .openURL(url))
    case .cashApp(let cashApp):
      guard let url = CashAppPaymentURL.make(cashtag: cashApp.cashtag, amount: share.total)
      else { return nil }
      return PreparedPaymentRequest(method: .cashApp, action: .openURL(url))
    case .iMessage(let recipient):
      guard
        let body = IMessageRequest.body(
          amount: share.total,
          currency: currency,
          context: requestNote)
      else { return nil }
      let composition = IMessageComposition(recipient: recipient.value, body: body)
      return PreparedPaymentRequest(method: .iMessage, action: .compose(composition))
    }
  }

  private var lastRequestedAt: Date? {
    requestedAt ?? share.participant.lastRequestedAt
  }

  private var requestButtonBottomMargin: CGFloat {
    guard preparedRequest != nil else { return 0 }
    return requestButtonHeight + (lastRequestedAt == nil ? 26 : 46)
  }

  private func requestButtonTitle(for method: PaymentMethod) -> String {
    let amount = share.total.formatted(.currency(code: currency))
    switch method {
    case .cashApp:
      return "Open \(amount) in Cash App"
    case .venmo, .iMessage:
      return "Request \(amount) in \(method.title)"
    case .none:
      return "Request \(amount)"
    }
  }

  private func requestButtonImage(for method: PaymentMethod) -> String {
    method == .iMessage ? "message.fill" : "arrow.up.right"
  }

  private func breakdownRow(
    title: String,
    subtitle: String?,
    amount: Double
  ) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      Text(amount, format: .currency(code: currency))
        .font(.body.monospacedDigit())
        .foregroundStyle(.secondary)
    }
  }

  private func formattedPercentage(_ fraction: Double) -> String {
    fraction.formatted(.percent.precision(.fractionLength(0...1)))
  }

  private func open(_ request: PreparedPaymentRequest) {
    switch request.action {
    case .openURL(let url):
      openURL(url) { accepted in
        if accepted {
          recordRequest()
        } else {
          requestErrorDescription =
            request.method == .venmo
            ? "Install Venmo to open this payment request."
            : "Cash App could not open this payment link."
        }
      }
    case .compose(let composition):
      guard MFMessageComposeViewController.canSendText() else {
        requestErrorDescription = "iMessage is not available on this device."
        return
      }
      messageComposition = composition
    }
  }

  private func recordRequest() {
    let date = Date()
    requestedAt = date
    onRequest(date)
  }
}

private struct PreparedPaymentRequest {
  enum Action {
    case openURL(URL)
    case compose(IMessageComposition)
  }

  let method: PaymentMethod
  let action: Action
}
