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
  /// The breakdown to share, once the split is final.
  let breakdown: ReceiptBreakdown?
  let onRequest: (Date) -> Void
  let onSavePerson: (Person) async -> Void
  let onDeletePerson: (Person) async -> Bool
  @State private var selectedPerson: Person?
  @State private var requester = PaymentRequester()
  @State private var requestedAt: Date?
  @State private var haptic = HapticEvent()
  @State private var viewedBreakdown: ViewedBreakdown?
  @Namespace private var breakdownTransition
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
        ReceiptBreakdownViewButton(
          breakdown: breakdown, viewed: $viewedBreakdown, transition: breakdownTransition)
      }
      .scrollEdgeEffectHidden(true, for: .bottom)
      .receiptBottomBar {
        if let preparedRequest {
          ReceiptActionButton(
            title: preparedRequest.title,
            systemImage: preparedRequest.systemImage,
            tint: preparedRequest.method.prominentColor
          ) {
            requester.open(
              preparedRequest, breakdown: breakdown, openURL: openURL, onSent: recordRequest)
          }
          .screenshotHighlight("request-button")
          // The caption hangs below the button so the button lines up with other bottom bars.
          .overlay(alignment: .bottom) {
            Text(lastRequestedCaption ?? " ")
              .font(.caption)
              .foregroundStyle(.secondary)
              .opacity(lastRequestedCaption == nil ? 0 : 1)
              .accessibilityHidden(lastRequestedCaption == nil)
              .fixedSize()
              .alignmentGuide(.bottom) { $0[.top] - ReceiptBottomBar.captionSpacing }
          }
          .animation(.smooth(duration: 0.3), value: lastRequestedCaption)
        }
      }
      .haptics(haptic)
      .paymentRequestPresentation(requester)
      .breakdownViewer($viewedBreakdown, in: breakdownTransition)
      .sheet(item: $selectedPerson) { selectedPerson in
        NavigationStack {
          PersonDetailView(
            person: selectedPerson,
            showsReceipts: false,
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
                ? "\(item.fraction.sharePercentText) share" : nil,
              amount: item.amount)
          }
        }
      }

      if !share.adjustments.isEmpty {
        Section {
          ForEach(share.adjustments) { adjustment in
            breakdownRow(
              title: adjustment.title,
              subtitle: adjustment.fraction.sharePercentText,
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

      if let reason = paymentDestination?.method.unsupportedCurrencyReason(currency) {
        Section {
          Label(reason, systemImage: "dollarsign.circle")
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
    PreparedPaymentRequest(
      share: share,
      destination: paymentDestination,
      currency: currency,
      note: requestNote,
      isSplitComplete: isSplitComplete)
  }

  private var lastRequestedAt: Date? {
    requestedAt ?? share.participant.lastRequestedAt
  }

  private var lastRequestedCaption: String? {
    lastRequestedAt.map { "Last requested \(PaymentRequestDateFormatter.formatted($0))" }
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
    haptic.play(.success)
  }
}
