import MessageUI
import SwiftUI

struct ReceiptParticipantBreakdownView: View {
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
  @Environment(\.openURL) private var openURL

  var body: some View {
    breakdownList
      .receiptBackground(backgroundStyle)
      .navigationTitle(share.participant.displayName)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if person != nil, !share.participant.source.isCurrentUser {
          ToolbarItem(placement: .topBarTrailing) {
            Button("View Contact", systemImage: "person.crop.circle") {
              selectedPerson = person
            }
          }
        }
      }
      .scrollEdgeEffectHidden(true, for: .bottom)
      .safeAreaBar(edge: .bottom) {
        if let preparedRequest {
          VStack(spacing: 6) {
            ReceiptActionButton(
              title: requestButtonTitle(for: preparedRequest.method),
              systemImage: requestButtonImage(for: preparedRequest.method),
              tint: preparedRequest.method.prominentColor
            ) {
              open(preparedRequest)
            }
            .screenshotHighlight("request-button")

            Text(lastRequestedCaption ?? " ")
              .font(.caption)
              .foregroundStyle(.secondary)
              .opacity(lastRequestedCaption == nil ? 0 : 1)
              .accessibilityHidden(lastRequestedCaption == nil)
          }
          .padding(.bottom, 8)
        }
      }
      .haptics(haptic)
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
            onDelete: deletePerson
          )
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button(role: .close) {
                self.selectedPerson = nil
              }
            }
          }
        }
      }
      .errorAlert("Couldn’t Open Payment Request", message: $requestErrorDescription)
  }

  /// The breakdown, subtitled with a missing payment method when there is one.
  @ViewBuilder
  private var breakdownList: some View {
    if !share.participant.source.isCurrentUser, paymentDestination == nil {
      breakdownContent
        .navigationSubtitle("No payment method set")
    } else {
      breakdownContent
    }
  }

  private var breakdownContent: some View {
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

  private var totalValue: some View {
    ShareTotalText(amount: isSplitComplete ? share.total : nil, currency: currency)
      .foregroundStyle(.secondary)
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

  private var lastRequestedCaption: String? {
    lastRequestedAt.map { "Last requested \(PaymentRequestDateFormatter.formatted($0))" }
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

  /// Plays the removal haptic here because the contact sheet dismisses itself on delete.
  private func deletePerson(_ person: Person) async -> Bool {
    let didDelete = await onDeletePerson(person)
    if didDelete { haptic.play(.removal) }
    return didDelete
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
