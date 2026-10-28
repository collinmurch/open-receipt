import SwiftUI

struct ReceiptRequestsView: View {
  let draft: ReceiptDraft
  let onFlush: () async -> Void
  /// Takes the person back to the receipt to assign the items no one shares yet.
  let onAssignItems: () -> Void
  /// Whether the receipt's breakdown is open over the page, to message or share to everyone.
  @Binding var isGroupSharePresented: Bool
  @State private var people: SavedPeopleModel
  /// The participants the saved people were last loaded for.
  @State private var loadedParticipantIDs: Set<ReceiptParticipant.ID>?
  /// A saved person opened from their card to add a payment method.
  @State private var editedPerson: Person?
  /// Where each person's contact card says to message them.
  @State private var contactRecipients: [ReceiptParticipant.ID: Person.IMessage.Recipient] = [:]
  @State private var viewedBreakdown: ViewedBreakdown?
  @State private var requester = PaymentRequester()
  @State private var haptic = HapticEvent()
  @AppStorage(PaymentSettings.defaultMethodKey) private var defaultPaymentMethod =
    PaymentSettings.initialDefaultMethod
  @AppStorage("groupShareIncludesEveryBreakdown") private var includesEveryBreakdown = false
  @Namespace private var breakdownTransition
  @Environment(\.contactClient) private var contactClient
  @Environment(\.openURL) private var openURL
  @Environment(\.colorScheme) private var colorScheme
  @Environment(ContactPhotos.self) private var photos: ContactPhotos?

  init(
    draft: ReceiptDraft,
    peopleStorage: PeopleFileStorage,
    isGroupSharePresented: Binding<Bool>,
    onFlush: @escaping () async -> Void,
    onAssignItems: @escaping () -> Void
  ) {
    self.draft = draft
    self.onFlush = onFlush
    self.onAssignItems = onAssignItems
    _isGroupSharePresented = isGroupSharePresented
    _people = State(initialValue: SavedPeopleModel(storage: peopleStorage))
  }

  var body: some View {
    let calculation = draft.splitCalculation
    let ownShare = calculation.participantShares.first { $0.participant.source.isCurrentUser }
    let requestShares = calculation.participantShares.filter {
      !$0.participant.source.isCurrentUser
    }

    ScrollView {
      VStack(spacing: 24) {
        if let ownShare {
          shareSection("Your Share") {
            shareCard(ownShare, calculation: calculation)
          }
        }

        if !requestShares.isEmpty {
          shareSection("Remaining Shares") {
            ForEach(requestShares) { share in
              shareCard(share, calculation: calculation)
            }
          }
        }

        if calculation.unassignedItemCount > 0 {
          assignItemsButton
        } else if !requestShares.isEmpty {
          groupShareButton
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
    .overlay { groupShare }
    .sheet(item: $editedPerson) { person in
      NavigationStack {
        PersonDetailView(
          person: person,
          showsReceipts: false,
          onSave: { await people.save($0) },
          onDelete: deletePerson
        )
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button(role: .close) { editedPerson = nil }
          }
        }
      }
    }
    .task(id: participantIDs) {
      await loadPeople()
    }
    .task(id: participantContactIdentifiers) {
      await loadMessageRecipients()
    }
    .breakdownViewer($viewedBreakdown, in: breakdownTransition)
    .haptics(haptic)
    .paymentRequestPresentation(requester)
    .errorAlert("Couldn’t Update Contact", message: $people.errorDescription)
  }

  private func shareSection(
    _ title: String,
    @ViewBuilder cards: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .accessibilityAddTraits(.isHeader)
      VStack(spacing: 12, content: cards)
    }
  }

  private func shareCard(
    _ share: ReceiptParticipantShare,
    calculation: ReceiptSplitCalculation
  ) -> some View {
    let isCurrentUser = share.participant.source.isCurrentUser
    let destination = paymentDestination(for: share)
    let contact = isCurrentUser ? nil : person(for: share)
    let breakdown = draft.breakdown(for: share, accentScheme: colorScheme, photos: photos)
    return ReceiptShareCard(
      share: share,
      paymentDestination: destination,
      blankPaymentMethod: contact?.paymentMethods.blankMethod,
      showsTotal: calculation.unassignedItemCount == 0,
      currency: draft.displayCurrency,
      onOpenContact: contact.map { contact in { editedPerson = contact } }
    ) {
      if let breakdown {
        let sourceID = "breakdown-\(share.id)"
        ViewBreakdownButton(sourceID: sourceID, transition: breakdownTransition) {
          viewedBreakdown = ViewedBreakdown(
            sourceID: sourceID, breakdown: breakdown,
            image: ReceiptBreakdownRenderer.image(for: breakdown))
        }
      }
    } actions: {
      if !isCurrentUser, let breakdown {
        requestAction(share, destination: destination, breakdown: breakdown)
      }
    }
    .screenshotHighlight("request-\(share.participant.displayName)")
  }

  /// The share's request, with when it was last requested or why it can't be below.
  private func requestAction(
    _ share: ReceiptParticipantShare,
    destination: PaymentDestination?,
    breakdown: ReceiptBreakdown
  ) -> some View {
    let state = PaymentRequestState(
      share: share, destination: destination, currency: draft.displayCurrency, note: requestNote)
    let contact: Person? = if case .needsPaymentMethod = state { person(for: share) } else { nil }
    let caption: String? =
      switch state {
      case .ready:
        share.participant.lastRequestedAt.map {
          "Last requested \(PaymentRequestDateFormatter.formatted($0))"
        }
      case .needsPaymentMethod:
        contact == nil
          ? "Add a payment method to request from \(share.participant.displayName)." : nil
      case .unavailable(let reason):
        reason
      }

    return VStack(spacing: 8) {
      if case .ready(let request) = state {
        ShareRequestButton(request: request) {
          sendRequest(request, for: share, breakdown: breakdown)
        }
      } else if let contact {
        Button {
          editedPerson = contact
        } label: {
          GlassActionLabel(title: "Add Payment Method", systemImage: "plus", isCompact: true)
        }
        .glassCapsule()
      }

      if let caption {
        Text(caption)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
  }

  private var assignItemsButton: some View {
    Button(action: onAssignItems) {
      HStack {
        Label("Assign all items before sending requests.", systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
        Spacer()
        Image(systemName: "chevron.forward")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(14)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    .accessibilityHint("Show the first item no one is assigned to")
  }

  /// Opens the receipt's breakdown over the page, to message or share to everyone.
  private var groupShareButton: some View {
    Button {
      haptic.play(.lift)
      withAnimation(.settle) { isGroupSharePresented = true }
    } label: {
      Label("Share Group Breakdown", systemImage: "square.and.arrow.up")
        .font(.body.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
    .buttonStyle(.glass)
    .opacity(isGroupSharePresented ? 0 : 1)
  }

  @ViewBuilder
  private var groupShare: some View {
    if isGroupSharePresented,
      let breakdowns = draft.allBreakdowns(accentScheme: colorScheme, photos: photos)
    {
      let others = draft.participants.filter { !$0.source.isCurrentUser }
      let recipients = others.compactMap { participant in
        messageRecipient(for: participant).map {
          GroupMessageRecipient(name: participant.displayName, recipient: $0)
        }
      }
      ReceiptGroupShareView(
        breakdowns: breakdowns,
        messageRecipients: recipients,
        unreachableNames: others.filter { messageRecipient(for: $0) == nil }.map(\.displayName),
        includesEveryBreakdown: $includesEveryBreakdown,
        onMessage: { selected in
          requester.message(selected, to: recipients.map(\.recipient), onSent: playSentHaptic)
        },
        onDismiss: endGroupShare
      )
      .transition(.identity)
    }
  }

  private func person(for share: ReceiptParticipantShare) -> Person? {
    people.people.person(for: share.participant)
  }

  /// Where to message `participant`: the iMessage recipient chosen for them, else their contact
  /// card's.
  private func messageRecipient(for participant: ReceiptParticipant) -> Person.IMessage.Recipient? {
    let person = people.people.person(for: participant)
    return person?.paymentMethods.iMessage?.recipient ?? contactRecipients[participant.id]
  }

  private func paymentDestination(for share: ReceiptParticipantShare) -> PaymentDestination? {
    person(for: share)?.paymentMethods.destination(globalDefault: defaultPaymentMethod)
  }

  private var requestNote: String {
    PaymentRequest.note(merchantName: draft.merchantName)
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
  /// to message breakdowns to. Loading with the page keeps the message actions ready before the
  /// group breakdown opens over it.
  private func loadMessageRecipients() async {
    let contactIdentifiers = participantContactIdentifiers
    let contacts = await contactClient.contacts(withIdentifiers: Array(contactIdentifiers.values))
    contactRecipients = contactIdentifiers.compactMapValues {
      contacts[$0]?.defaultRecipient(Person.IMessage.Recipient.self)
    }
  }

  private func endGroupShare() {
    withAnimation(.settle) { isGroupSharePresented = false }
  }

  private func sendRequest(
    _ request: PaymentRequest,
    for share: ReceiptParticipantShare,
    breakdown: ReceiptBreakdown
  ) {
    requester.open(
      request,
      breakdown: breakdown,
      openURL: openURL,
      onSent: { recordRequest(for: share.participant.id) })
  }

  /// Plays the removal haptic here because the contact sheet dismisses itself on delete.
  private func deletePerson(_ person: Person) async -> Bool {
    let didDelete = await people.delete(person)
    if didDelete { haptic.play(.removal) }
    return didDelete
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
