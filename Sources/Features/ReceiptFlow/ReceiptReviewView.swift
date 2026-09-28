import SwiftUI

private enum ReceiptReviewPage: Hashable {
  case receipt
  case payments
}

struct ReceiptReviewView: View {
  let draft: ReceiptDraft
  let showsSampleNotice: Bool
  let pages: ReceiptPagesEditor
  let onClose: (() -> Void)?
  let onFlush: () async -> Void
  @State private var isEditing = false
  @State private var selectedItemID: ReceiptDraftItem.ID?
  @State private var selectedParticipantIDs: Set<ReceiptParticipant.ID> = []
  @State private var hasInitializedParticipantSelection = false
  @State private var selectedPage: ReceiptReviewPage
  @State private var isPeoplePresented = false
  @State private var isPagesPresented = false
  @State private var haptic = HapticEvent()
  @ScaledMetric(relativeTo: .caption2) private var stripHeight = ParticipantStrip.baseHeight
  @ScaledMetric(relativeTo: .body) private var actionButtonClearance: CGFloat = 76
  @Environment(\.receiptBackgroundMotion) private var motion
  @Environment(\.contactClient) private var contactClient
  @Environment(\.peopleStorageClient) private var peopleStorage
  @Environment(\.receiptStorageClient) private var storage
  @Environment(\.colorScheme) private var colorScheme

  init(
    draft: ReceiptDraft,
    showsSampleNotice: Bool,
    pages: ReceiptPagesEditor,
    startsInEditing: Bool,
    onClose: (() -> Void)?,
    onFlush: @escaping () async -> Void
  ) {
    self.draft = draft
    self.showsSampleNotice = showsSampleNotice
    self.pages = pages
    self.onClose = onClose
    self.onFlush = onFlush
    _isEditing = State(initialValue: startsInEditing)
    _selectedPage = State(initialValue: draft.isCompleted ? .payments : .receipt)
  }

  var body: some View {
    reviewContent
      .tint(draft.backgroundStyle.accentColor(for: colorScheme))
      .toolbarVisibility(isEditing ? .hidden : .visible, for: .tabBar)
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
          peopleStorage: peopleStorage,
          receiptStorage: storage)
      }
      .sheet(isPresented: $isPagesPresented) {
        ReceiptPagesView(receiptID: draft.id, editor: pages, style: draft.backgroundStyle)
          .environment(\.receiptBackgroundMotion, motion)
      }
      .haptics(haptic)
      .sensoryFeedback(.success, trigger: draft.isCompleted) { wasCompleted, isCompleted in
        !wasCompleted && isCompleted
      }
      .onAppear(perform: initializeParticipantSelection)
      .task { await refreshContactAvatars() }
      .overlay(alignment: .bottom) {
        if !draft.isCompleted && !isEditing {
          completionButton
            .offset(y: 16)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
      }
  }

  @ViewBuilder
  private var reviewContent: some View {
    if draft.isCompleted {
      receiptTabs
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
    } else {
      receiptList
    }
  }

  private var receiptTabs: some View {
    TabView(selection: $selectedPage) {
      Tab("Receipt", systemImage: "doc.text", value: ReceiptReviewPage.receipt) {
        receiptList
      }

      Tab("Payments", systemImage: "dollarsign", value: ReceiptReviewPage.payments) {
        ReceiptRequestsView(
          draft: draft,
          adjustmentMethod: draft.adjustmentSplitMethod,
          onFlush: onFlush)
      }
    }
    .tabViewStyle(.tabBarOnly)
    .tabBarMinimizeBehavior(.never)
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
        displayCurrency: displayCurrency,
        haptic: $haptic,
        onSelectItem: { selectedItemID = $0 }
      )
      ReceiptTotalsSection(
        draft: draft,
        isEditing: isEditing,
        displayCurrency: displayCurrency,
        haptic: $haptic
      )

      if isEditing {
        ReceiptEditorValidationSection(issues: draft.validationIssues)
      } else {
        ReceiptWarningsSection(warnings: draft.warnings)
      }
    }
    .contentMargins(.top, isEditing ? 0 : stripHeight + 16, for: .scrollContent)
    .contentMargins(
      .bottom, !draft.isCompleted && !isEditing ? actionButtonClearance : 24, for: .scrollContent
    )
    .receiptBackground(draft.backgroundStyle)
    .overlay(alignment: .top) {
      if !isEditing {
        ParticipantStrip(
          participants: draft.participants,
          amountsOwed: participantAmountsOwed,
          currency: displayCurrency,
          selectedParticipantIDs: selectedParticipantIDs,
          onSelect: toggleParticipantSelection,
          onManagePeople: { isPeoplePresented = true }
        )
        .padding(.horizontal)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
  }

  private var participantAmountsOwed: [ReceiptParticipant.ID: Double] {
    Dictionary(
      uniqueKeysWithValues: draft.splitCalculation.participantShares.map { ($0.id, $0.total) })
  }

  private var completionButton: some View {
    ReceiptActionButton(title: "Done", systemImage: "checkmark", style: draft.backgroundStyle) {
      withAnimation(.bouncy(duration: 0.65, extraBounce: 0.12)) {
        draft.complete()
        selectedPage = .payments
      }
      Task { await onFlush() }
    }
    .accessibilityLabel("Ready for Payments")
    .accessibilityHint("Show payment requests for this receipt")
  }

  private var navigationTitle: String {
    if isEditing { return "Edit Receipt" }
    if selectedPage == .payments { return "Request Payments" }
    return draft.merchantName.isEmpty ? "Receipt" : draft.merchantName
  }

  @ToolbarContentBuilder
  private var receiptToolbar: some ToolbarContent {
    ToolbarItem(placement: .principal) {
      Text(navigationTitle)
        .font(.headline)
        .lineLimit(1)
    }

    if isEditing {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Done", systemImage: "checkmark", action: finishEditing)
          .labelStyle(.iconOnly)
      }
    } else {
      if let onClose {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close", systemImage: "xmark", action: onClose)
            .labelStyle(.iconOnly)
        }
      }

      ToolbarItem(placement: .topBarTrailing) {
        Button("Pages", systemImage: "doc.viewfinder") { isPagesPresented = true }
          .labelStyle(.iconOnly)
      }

      if selectedPage == .receipt {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Edit", systemImage: "pencil", action: beginEditing)
            .labelStyle(.iconOnly)
        }
      }
    }
  }

  private var receiptFields: some View {
    Section("Receipt") {
      TextField("Merchant", text: binding(\.merchantName))
        .textContentType(.organizationName)
      Picker("Split Tax/Tip", selection: binding(\.adjustmentSplitMethod)) {
        ForEach(ReceiptAdjustmentSplitMethod.allCases) { method in
          Text(method.title)
            .tag(method)
        }
      }
      .pickerStyle(.menu)
      DatePicker("Date", selection: binding(\.purchaseDate), displayedComponents: .date)
      NavigationLink {
        ReceiptCurrencyPicker(
          selection: binding(\.currency),
          backgroundStyle: draft.backgroundStyle)
      } label: {
        LabeledContent("Currency", value: draft.normalizedCurrency)
      }
    }
  }

  private var displayCurrency: String {
    let currency = draft.normalizedCurrency
    return currency.count == 3 ? currency : "USD"
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
        currency: displayCurrency,
        onSplit: { count in
          draft.splitItem(id: id, into: count)
        },
        onDelete: {
          draft.removeItem(id: id)
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

  private func initializeParticipantSelection() {
    guard !hasInitializedParticipantSelection else { return }
    hasInitializedParticipantSelection = true
    let defaultParticipant =
      draft.participants.first { $0.source.isCurrentUser }
      ?? draft.participants.first
    if let defaultParticipant {
      selectedParticipantIDs.insert(defaultParticipant.id)
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
    for participant in draft.participants {
      guard let identifier = participant.source.contactIdentifier,
        let avatar = try? await contactClient.fetchAvatar(identifier)
      else { continue }
      draft.updateAvatar(avatar, forContactIdentifier: identifier)
    }
  }

  private func binding<Value>(
    _ keyPath: ReferenceWritableKeyPath<ReceiptDraft, Value>
  ) -> Binding<Value> {
    Binding(
      get: { draft[keyPath: keyPath] },
      set: { draft[keyPath: keyPath] = $0 })
  }
}
