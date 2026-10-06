import SwiftUI

/// What the payments page has lifted out of its list.
enum ReceiptPaymentsFocus: Hashable {
  /// A person's share, to request or share it.
  case share(ReceiptParticipant.ID)
  /// The receipt's breakdown, to message or share it to everyone.
  case group
}

struct ReceiptRequestsView: View {
  let draft: ReceiptDraft
  let onFlush: () async -> Void
  @Binding var focus: ReceiptPaymentsFocus?
  @State private var people: SavedPeopleModel
  /// The participants the saved people were last loaded for.
  @State private var loadedParticipantIDs: Set<ReceiptParticipant.ID>?
  @State private var selectedShareID: ReceiptParticipant.ID?
  @State private var focusedRowFrame: CGRect?
  /// Where each focused person's contact card says to message them.
  @State private var messageRecipients: [ReceiptParticipant.ID: Person.IMessage.Recipient] = [:]
  @State private var isFocusedRowPressed = false
  @State private var requester = PaymentRequester()
  @State private var haptic = HapticEvent()
  @AppStorage(PaymentSettings.defaultMethodKey) private var defaultPaymentMethod =
    PaymentSettings.initialDefaultMethod
  @AppStorage("groupShareIncludesEveryBreakdown") private var includesEveryBreakdown = false
  @Environment(\.contactClient) private var contactClient
  @Environment(\.openURL) private var openURL
  @Environment(\.colorScheme) private var colorScheme

  init(
    draft: ReceiptDraft,
    peopleStorage: PeopleStorageClient,
    focus: Binding<ReceiptPaymentsFocus?>,
    onFlush: @escaping () async -> Void
  ) {
    self.draft = draft
    self.onFlush = onFlush
    _focus = focus
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
          shareRow(ownShare, calculation: calculation)
        }
      }

      if !requestShares.isEmpty {
        Section {
          ForEach(requestShares) { share in
            shareRow(share, calculation: calculation)
          }
        } header: {
          Text("Remaining Shares")
        } footer: {
          if calculation.unassignedItemCount == 0 {
            groupShareButton
          }
        }
      }

      if calculation.unassignedItemCount > 0 {
        Section {
          Label {
            Text("Assign \(unassignedDescription(calculation)) before you send requests.")
          } icon: {
            Image(systemName: "exclamationmark.triangle")
          }
          .foregroundStyle(.orange)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .overlay { shareFocus(calculation) }
    .overlay { groupShare }
    .navigationDestination(item: $selectedShareID) { id in
      breakdownDestination(id: id)
    }
    .task(id: participantIDs) {
      await loadPeople()
    }
    .task(id: participantContactIdentifiers) {
      await loadMessageRecipients()
    }
    .haptics(haptic)
    .paymentRequestPresentation(requester)
    .errorAlert("Couldn’t Update Contact", message: $people.errorDescription)
  }

  private func shareRow(
    _ share: ReceiptParticipantShare,
    calculation: ReceiptSplitCalculation
  ) -> some View {
    ReceiptShareRow(
      content: rowContent(share, calculation: calculation),
      isFocused: share.id == focusedShareID,
      isLiftedOut: share.id == focusedShareID && focusedRowFrame != nil,
      onTap: { selectedShareID = share.id },
      onFocus: { focusShare(share.id, isPressed: $0) },
      onFocusedFrameChange: { focusedRowFrame = $0 }
    )
    .screenshotHighlight("request-\(share.participant.displayName)")
  }

  private func rowContent(
    _ share: ReceiptParticipantShare,
    calculation: ReceiptSplitCalculation
  ) -> ReceiptShareRowContent {
    ReceiptShareRowContent(
      share: share,
      paymentDestination: paymentDestination(for: share),
      showsPaymentDestination: !share.participant.source.isCurrentUser,
      showsTotal: calculation.unassignedItemCount == 0,
      currency: draft.displayCurrency)
  }

  @ViewBuilder
  private func shareFocus(_ calculation: ReceiptSplitCalculation) -> some View {
    if let focusedShareID, let focusedRowFrame,
      let share = calculation.participantShares.first(where: { $0.id == focusedShareID })
    {
      let breakdown = draft.breakdown(for: share, accentScheme: colorScheme)
      ReceiptShareFocusView(
        content: rowContent(share, calculation: calculation),
        rowFrame: focusedRowFrame,
        startsPressed: isFocusedRowPressed,
        request: preparedRequest(for: share, calculation: calculation),
        unavailableRequestReason: unavailableRequestReason(for: share, calculation: calculation),
        breakdown: breakdown,
        messageRecipient: messageRecipients[share.id],
        onRequest: { request in
          requester.open(
            request,
            breakdown: breakdown,
            openURL: openURL,
            onSent: { recordRequest(for: share.participant.id) })
        },
        onMessageBreakdown: { recipient in
          guard let breakdown else { return }
          requester.message([breakdown], to: [recipient], onSent: playSentHaptic)
        },
        onDismiss: endFocus
      )
      .transition(.identity)
    }
  }

  /// Opens the receipt's breakdown over the page, to message or share to everyone.
  private var groupShareButton: some View {
    HStack {
      Spacer()
      Button {
        haptic.play(.lift)
        withAnimation(.settle) { focus = .group }
      } label: {
        Label("Share Breakdown", systemImage: "square.and.arrow.up")
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
      }
      .buttonStyle(.glass)
      .opacity(focus == .group ? 0 : 1)
      Spacer()
    }
    .textCase(nil)
    .padding(.top, 20)
  }

  @ViewBuilder
  private var groupShare: some View {
    if focus == .group, let breakdowns = draft.allBreakdowns(accentScheme: colorScheme) {
      let others = draft.participants.filter { !$0.source.isCurrentUser }
      ReceiptGroupShareView(
        breakdowns: breakdowns,
        messageRecipients: others.compactMap { participant in
          messageRecipients[participant.id].map {
            GroupMessageRecipient(name: participant.displayName, recipient: $0)
          }
        },
        unreachableNames: others.filter { messageRecipients[$0.id] == nil }.map(\.displayName),
        includesEveryBreakdown: $includesEveryBreakdown,
        onMessage: { selected in
          let recipients = others.compactMap { messageRecipients[$0.id] }
          requester.message(selected, to: recipients, onSent: playSentHaptic)
        },
        onDismiss: endFocus
      )
      .transition(.identity)
    }
  }

  @ViewBuilder
  private func breakdownDestination(id: ReceiptParticipant.ID) -> some View {
    let calculation = draft.splitCalculation
    if let share = calculation.participantShares.first(where: { $0.id == id }) {
      ReceiptParticipantBreakdownView(
        share: share,
        person: person(for: share),
        currency: draft.displayCurrency,
        adjustmentMethod: draft.adjustmentSplitMethod,
        backgroundStyle: draft.backgroundStyle,
        requestNote: requestNote,
        globalDefault: defaultPaymentMethod,
        isSplitComplete: calculation.unassignedItemCount == 0,
        breakdown: draft.breakdown(for: share, accentScheme: colorScheme),
        onRequest: {
          draft.recordRequest(for: share.participant.id, at: $0)
          Task { await onFlush() }
        },
        onSavePerson: { await people.save($0) },
        onDeletePerson: { await people.delete($0) }
      )
    } else {
      ContentUnavailableView(
        "Person Not Found", systemImage: "person.crop.circle.badge.questionmark")
    }
  }

  private func person(for share: ReceiptParticipantShare) -> Person? {
    ReceiptPersonResolver.person(for: share.participant, in: people.people)
  }

  private func paymentDestination(for share: ReceiptParticipantShare) -> PaymentDestination? {
    person(for: share)?.paymentMethods.destination(globalDefault: defaultPaymentMethod)
  }

  private func preparedRequest(
    for share: ReceiptParticipantShare,
    calculation: ReceiptSplitCalculation
  ) -> PreparedPaymentRequest? {
    PreparedPaymentRequest(
      share: share,
      destination: paymentDestination(for: share),
      currency: draft.displayCurrency,
      note: requestNote,
      isSplitComplete: calculation.unassignedItemCount == 0)
  }

  private func unavailableRequestReason(
    for share: ReceiptParticipantShare,
    calculation: ReceiptSplitCalculation
  ) -> String? {
    PreparedPaymentRequest.unavailableReason(
      share: share,
      destination: paymentDestination(for: share),
      currency: draft.displayCurrency,
      isSplitComplete: calculation.unassignedItemCount == 0)
  }

  private var requestNote: String {
    PreparedPaymentRequest.note(merchantName: draft.merchantName)
  }

  private func unassignedDescription(_ calculation: ReceiptSplitCalculation) -> String {
    let count = calculation.unassignedItemCount
    let items = String(inflecting: "^[\(count) item](inflect: true)")
    let amount = calculation.unassignedItemTotal.formatted(.currency(code: draft.displayCurrency))
    return "\(items) (\(amount))"
  }

  private var focusedShareID: ReceiptParticipant.ID? {
    if case .share(let id) = focus { return id }
    return nil
  }

  private var participantIDs: Set<ReceiptParticipant.ID> {
    Set(draft.participants.map(\.id))
  }

  /// Reloads saved people when participants change, since this page stays built while people are
  /// added elsewhere and would otherwise miss their payment methods.
  private func loadPeople() async {
    let ids = participantIDs
    guard loadedParticipantIDs != ids else { return }
    await people.load()
    await people.adoptContactPaymentDefaults(from: contactClient)
    if people.errorDescription == nil { loadedParticipantIDs = ids }
  }

  /// The contact card behind each participant picked from Contacts.
  private var participantContactIdentifiers: [ReceiptParticipant.ID: String] {
    draft.participants.reduce(into: [:]) { identifiers, participant in
      if case .contact(let identifier) = participant.source {
        identifiers[participant.id] = identifier
      }
    }
  }

  /// Looks up everyone's contact card for a phone number, or an email address when one has none,
  /// to message breakdowns to. Loading with the page keeps the message actions ready before a
  /// share or the group breakdown opens over it.
  private func loadMessageRecipients() async {
    let contactIdentifiers = participantContactIdentifiers
    guard !contactIdentifiers.isEmpty,
      let contacts = try? await contactClient.fetchContacts(Array(contactIdentifiers.values))
    else {
      messageRecipients = [:]
      return
    }
    let contactsByIdentifier = Dictionary(
      contacts.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
    messageRecipients = contactIdentifiers.compactMapValues {
      contactsByIdentifier[$0]?.defaultRecipient(Person.IMessage.Recipient.self)
    }
  }

  private func focusShare(_ id: ReceiptParticipant.ID, isPressed: Bool) {
    guard focus == nil else { return }
    haptic.play(.lift)
    isFocusedRowPressed = isPressed
    withAnimation(.settle) {
      focus = .share(id)
    }
  }

  private func endFocus() {
    withAnimation(.settle) {
      focus = nil
      focusedRowFrame = nil
    }
  }

  private func recordRequest(for participantID: ReceiptParticipant.ID) {
    draft.recordRequest(for: participantID, at: Date())
    playSentHaptic()
    Task { await onFlush() }
  }

  private func playSentHaptic() {
    haptic.play(.success)
  }
}
