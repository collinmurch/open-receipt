import SwiftUI

private enum ReceiptReviewSheet: Hashable {
  case pages
  case people
}

private enum ReceiptReviewGlass: Hashable {
  case bottomBar
}

struct ReceiptReviewView: View {
  @Bindable var draft: ReceiptDraft
  let showsSampleNotice: Bool
  let pages: ReceiptPagesEditor
  let onFlush: () async -> Void
  @State private var isEditing = false
  @State private var selectedItemID: ReceiptDraftItem.ID?
  @State private var selectedParticipantIDs: Set<ReceiptParticipant.ID> = []
  @State private var selectedPage: ReceiptReviewPage
  @State private var isPeoplePresented = false
  @State private var isPagesPresented = false
  @State private var haptic = HapticEvent()
  @Namespace private var sheetTransition
  @Namespace private var glassTransition
  @Environment(\.receiptBackgroundMotion) private var motion
  @Environment(\.contactClient) private var contactClient
  @Environment(\.peopleStorageClient) private var peopleStorage
  @Environment(\.colorScheme) private var colorScheme

  init(
    draft: ReceiptDraft,
    showsSampleNotice: Bool,
    pages: ReceiptPagesEditor,
    startsInEditing: Bool,
    onFlush: @escaping () async -> Void
  ) {
    self.draft = draft
    self.showsSampleNotice = showsSampleNotice
    self.pages = pages
    self.onFlush = onFlush
    _isEditing = State(initialValue: startsInEditing)
    _selectedPage = State(initialValue: draft.isCompleted ? .payments : .receipt)
  }

  var body: some View {
    reviewContent
      .scrollEdgeEffectHidden(true, for: .bottom)
      .safeAreaBar(edge: .bottom) { bottomBar }
      .tint(draft.backgroundStyle.accentColor(for: colorScheme))
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
      .scrollDismissesKeyboard(.interactively)
      .toolbar { receiptToolbar }
      .navigationDestination(item: $selectedItemID) { id in
        itemDestination(id: id)
      }
      .sheet(isPresented: $isPeoplePresented, onDismiss: finishManagingPeople) {
        ReceiptPeopleView(
          draft: draft,
          contactClient: contactClient,
          peopleStorage: peopleStorage
        )
        .navigationTransition(.zoom(sourceID: ReceiptReviewSheet.people, in: sheetTransition))
      }
      .sheet(isPresented: $isPagesPresented) {
        ReceiptPagesView(receiptID: draft.id, editor: pages, style: draft.backgroundStyle)
          .environment(\.receiptBackgroundMotion, motion)
          .navigationTransition(.zoom(sourceID: ReceiptReviewSheet.pages, in: sheetTransition))
      }
      .haptics(haptic)
      .sensoryFeedback(.success, trigger: draft.isCompleted) { wasCompleted, isCompleted in
        !wasCompleted && isCompleted
      }
      .task { await refreshContactAvatars() }
  }

  /// Both pages of a completed receipt stay built, and switching only changes which one shows.
  /// Rebuilding a page on every switch stalls the frame that starts the switcher's animation.
  private var reviewContent: some View {
    let showsPayments = draft.isCompleted && selectedPage == .payments && !isEditing
    return ZStack {
      receiptList
        .pageVisibility(!showsPayments)
      if draft.isCompleted {
        ReceiptRequestsView(draft: draft, peopleStorage: peopleStorage, onFlush: onFlush)
          .pageVisibility(showsPayments)
      }
    }
  }

  private var receiptList: some View {
    List {
      if showsSampleNotice && !isEditing {
        Section {
          Label("Sample data for interface development", systemImage: "hammer")
            .foregroundStyle(.secondary)
        }
      }

      if isEditing {
        receiptFields
      }

      ReceiptItemsSection(
        draft: draft,
        isEditing: isEditing,
        selectedParticipantIDs: $selectedParticipantIDs,
        haptic: $haptic,
        onSelectItem: { selectedItemID = $0 }
      )
      ReceiptTotalsSection(
        draft: draft,
        isEditing: isEditing,
        haptic: $haptic
      )

      if isEditing {
        ReceiptEditorValidationSection(issues: draft.validationIssues)
      } else {
        ReceiptWarningsSection(warnings: draft.warnings)
      }
    }
    .scrollContentBackground(.hidden)
    .safeAreaBar(edge: .top) {
      GlassEffectContainer {
        if !isEditing {
          ParticipantStrip(
            participants: draft.participants,
            amountsOwed: participantAmountsOwed,
            currency: draft.displayCurrency,
            selectedParticipantIDs: selectedParticipantIDs,
            onSelect: toggleParticipantSelection,
            onManagePeople: { isPeoplePresented = true },
            addTransition: (id: ReceiptReviewSheet.people, namespace: sheetTransition)
          )
          .receiptTopBarPadding()
        }
      }
    }
  }

  /// Done while the receipt is being split, then the switch between its items and payments. Done
  /// morphs into the switcher when the receipt is completed.
  private var bottomBar: some View {
    GlassEffectContainer {
      if !isEditing {
        if draft.isCompleted {
          ReceiptPageSwitcher(selection: $selectedPage)
            .glassEffectID(ReceiptReviewGlass.bottomBar, in: glassTransition)
        } else {
          completionButton
            .glassEffectID(ReceiptReviewGlass.bottomBar, in: glassTransition)
        }
      }
    }
    .padding(.bottom, 8)
    .animation(.bouncy(duration: 0.5, extraBounce: 0.1), value: draft.isCompleted)
    .animation(.smooth(duration: 0.35), value: isEditing)
  }

  private var participantAmountsOwed: [ReceiptParticipant.ID: Double] {
    Dictionary(
      uniqueKeysWithValues: draft.splitCalculation.participantShares.map { ($0.id, $0.total) })
  }

  private var completionButton: some View {
    ReceiptActionButton(
      title: "Done", systemImage: "checkmark", tint: draft.backgroundStyle.prominentColor
    ) {
      draft.complete()
      selectedPage = .payments
      Task { await onFlush() }
    }
    .accessibilityLabel("Ready for Payments")
    .accessibilityHint("Show payment requests for this receipt")
  }

  private var navigationTitle: String {
    if isEditing { return "Edit Receipt" }
    if draft.isCompleted && selectedPage == .payments { return "Request Payments" }
    return draft.merchantName.isEmpty ? "Receipt" : draft.merchantName
  }

  @ToolbarContentBuilder
  private var receiptToolbar: some ToolbarContent {
    if isEditing {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done", systemImage: "checkmark", role: .confirm, action: finishEditing)
          .buttonStyle(.glassProminent)
      }
    } else {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Pages", systemImage: "doc.viewfinder") { isPagesPresented = true }
      }
      .matchedTransitionSource(id: ReceiptReviewSheet.pages, in: sheetTransition)

      if selectedPage == .receipt || !draft.isCompleted {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Edit", systemImage: "pencil", action: beginEditing)
        }
      }
    }
  }

  private var receiptFields: some View {
    Section("Receipt") {
      TextField("Merchant", text: $draft.merchantName)
        .textContentType(.organizationName)
      Picker("Split Tax/Tip", selection: $draft.adjustmentSplitMethod) {
        ForEach(ReceiptAdjustmentSplitMethod.allCases) { method in
          Text(method.title)
            .tag(method)
        }
      }
      .pickerStyle(.menu)
      DatePicker("Date", selection: $draft.purchaseDate, displayedComponents: .date)
      NavigationLink {
        ReceiptCurrencyPicker(
          selection: $draft.currency,
          backgroundStyle: draft.backgroundStyle)
      } label: {
        LabeledContent("Currency", value: draft.normalizedCurrency)
      }
    }
  }

  private func itemBinding(for id: ReceiptDraftItem.ID) -> Binding<ReceiptDraftItem>? {
    guard let initialItem = draft.items.first(where: { $0.id == id }) else { return nil }
    return Binding(
      get: {
        draft.items.first(where: { $0.id == id }) ?? initialItem
      },
      set: { item in
        guard let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
        draft.items[index] = item
      })
  }

  @ViewBuilder
  private func itemDestination(id: ReceiptDraftItem.ID) -> some View {
    if let item = itemBinding(for: id) {
      ReceiptItemEditorView(
        item: item,
        currency: draft.displayCurrency,
        onSplit: { count in
          draft.splitItem(id: id, into: count)
          haptic.play(.success)
        },
        onDelete: {
          draft.removeItem(id: id)
          haptic.play(.removal)
        })
    } else {
      ContentUnavailableView("Item Not Found", systemImage: "questionmark.square.dashed")
    }
  }

  private func beginEditing() {
    withAnimation(.smooth(duration: 0.35)) {
      isEditing = true
    }
  }

  private func toggleParticipantSelection(_ id: ReceiptParticipant.ID) {
    haptic.play(.selection)
    withAnimation(.smooth(duration: 0.25)) {
      if selectedParticipantIDs.contains(id) {
        selectedParticipantIDs.remove(id)
      } else {
        selectedParticipantIDs.insert(id)
      }
    }
  }

  private func removeMissingParticipantSelections() {
    let participantIDs = Set(draft.participants.map(\.id))
    selectedParticipantIDs.formIntersection(participantIDs)
  }

  private func finishEditing() {
    draft.normalizeEditableFields()
    selectedItemID = nil
    withAnimation(.smooth(duration: 0.35)) {
      isEditing = false
    }
    Task { await onFlush() }
  }

  private func finishManagingPeople() {
    removeMissingParticipantSelections()
    Task { await onFlush() }
  }

  private func refreshContactAvatars() async {
    let fetchAvatar = contactClient.fetchAvatar
    let identifiers = Set(draft.participants.compactMap(\.source.contactIdentifier))
    await withTaskGroup(of: (String, Data)?.self) { group in
      for identifier in identifiers {
        group.addTask {
          guard let avatar = try? await fetchAvatar(identifier) else { return nil }
          return (identifier, avatar)
        }
      }
      for await case (let identifier, let avatar)? in group {
        draft.updateAvatar(avatar, forContactIdentifier: identifier)
      }
    }
  }
}

extension View {
  /// Shows or hides one page of a receipt without removing it, so switching back is immediate.
  /// The switch is a cut: fading would smear the pages' glass and scroll edge effects.
  fileprivate func pageVisibility(_ isVisible: Bool) -> some View {
    opacity(isVisible ? 1 : 0)
      .allowsHitTesting(isVisible)
      .accessibilityHidden(!isVisible)
  }
}
