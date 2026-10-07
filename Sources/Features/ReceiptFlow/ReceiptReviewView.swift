import SwiftUI

private enum ReceiptReviewSheet: Hashable {
  case people
}

struct ReceiptReviewView: View {
  /// How far the bottom bar slides to leave the screen while editing. It only slides: fading glass
  /// renders it against the page background, which covers the rows behind it.
  private static let bottomBarExitDistance: CGFloat = 300

  @Bindable var draft: ReceiptDraft
  let showsSampleNotice: Bool
  let pages: ReceiptPagesEditor
  let onFlush: () async -> Void
  @State private var isEditing = false
  @State private var selectedItemID: ReceiptDraftItem.ID?
  @State private var selectedParticipantIDs: Set<ReceiptParticipant.ID> = []
  @State private var seededItemID: ReceiptDraftItem.ID?
  @State private var sweep: ReceiptItemSweep?
  @State private var itemRowFrames = ReceiptItemRowFrames()
  @State private var focusedItemID: ReceiptDraftItem.ID?
  @State private var paymentsFocus: ReceiptPaymentsFocus?
  @State private var focusedRowFrame: CGRect?
  @State private var isFocusedItemPressed = false
  @State private var participantStripFrame: CGRect?
  @State private var selectedPage: ReceiptReviewPage
  @State private var isPeoplePresented = false
  @State private var isPagesPresented = false
  @State private var haptic = HapticEvent()
  @Namespace private var sheetTransition
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
      .receiptBottomBar { bottomBar }
      .overlay { itemFocus }
      .navigationBarBackButtonHidden(isFocusing)
      .tint(draft.backgroundStyle.accentColor(for: colorScheme))
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
      .scrollDismissesKeyboard(.interactively)
      .dismissesKeyboardOnTap()
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
      }
      .haptics(haptic)
      .sensoryFeedback(.success, trigger: draft.isCompleted) { wasCompleted, isCompleted in
        !wasCompleted && isCompleted
      }
      .task { await refreshContactAvatars() }
      .task { await ReceiptCurrencyPicker.prepareCatalog() }
  }

  /// Both pages of a completed receipt stay built, and switching only changes which one shows.
  /// Rebuilding a page on every switch stalls the frame that starts the switcher's animation.
  private var reviewContent: some View {
    ZStack {
      receiptList
        .pageVisibility(!showsPayments)
      if draft.isCompleted {
        ReceiptRequestsView(
          draft: draft,
          peopleStorage: peopleStorage,
          focus: $paymentsFocus,
          onFlush: onFlush
        )
        .pageVisibility(showsPayments)
      }
    }
  }

  private var showsPayments: Bool {
    draft.isCompleted && selectedPage == .payments && !isEditing
  }

  private var receiptList: some View {
    List {
      if showsSampleNotice {
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
        seededItemID: $seededItemID,
        haptic: $haptic,
        focusedItemID: focusedItemID,
        isFocusPresented: isItemFocusPresented,
        rowFrames: itemRowFrames,
        onSelectItem: { selectedItemID = $0 },
        onFocusItem: focusItem,
        onFocusedRowFrameChange: { focusedRowFrame = $0 }
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
    // Attached before the people bar, so a sweep starts only over the list.
    .gesture(
      TwoFingerSweepGesture(
        isEnabled: !selectedParticipantIDs.isEmpty && !isEditing && !isFocusing,
        onChanged: sweepItems(at:),
        onEnded: { sweep = nil }
      )
    )
    // Editing adds the receipt's fields above the items. Holding the top edge still lets them push
    // the items down; holding the items still instead places the fields by estimated height and
    // jumps once they're measured.
    .defaultScrollAnchor(.top, for: .sizeChanges)
    .safeAreaBar(edge: .top) {
      // Editing collapses the bar rather than removing the strip, so the list rises with it and
      // the strip slides up behind the navigation bar instead of over it.
      ParticipantStrip(
        participants: draft.participants,
        amountsOwed: draft.splitCalculation.amountsOwed,
        currency: draft.displayCurrency,
        selectedParticipantIDs: selectedParticipantIDs,
        onSelect: toggleParticipantSelection,
        onManagePeople: { isPeoplePresented = true },
        onClearSelection: clearParticipantSelection,
        addTransition: isFocusingItem ? nil : peopleSheetTransition
      )
      .onGeometryChange(for: CGRect.self) { proxy in
        proxy.frame(in: .global)
      } action: { frame in
        participantStripFrame = frame
      }
      .opacity(isItemFocusPresented ? 0 : 1)
      .transaction(value: isItemFocusPresented) { $0.animation = nil }
      .receiptTopBarPadding()
      .frame(height: isEditing ? 0 : nil, alignment: .bottom)
      .clipped()
      .allowsHitTesting(!isEditing)
      .accessibilityHidden(isEditing)
    }
  }

  /// Done while the receipt is being split, then the switch between its items and payments. The
  /// switcher's glass is drawn by UIKit, so Done dematerializes and the switcher scales in rather
  /// than morphing. Editing slides the bar off-screen but keeps it in place: changing the bottom
  /// inset hides the rows under the bar until the change settles.
  private var bottomBar: some View {
    ZStack(alignment: .bottom) {
      GlassEffectContainer {
        if !draft.isCompleted {
          completionButton
        }
      }
      if draft.isCompleted {
        ReceiptPageSwitcher(
          selection: $selectedPage,
          tint: draft.backgroundStyle.accentColor(for: colorScheme)
        )
        // The tab bar draws the bar's margin below its capsule itself.
        .padding(.bottom, -ReceiptBottomBar.screenEdgeInset)
        .transition(.scale(scale: ReceiptPageSwitcher.entranceScale).combined(with: .opacity))
      }
    }
    .animation(.glassMorph, value: draft.isCompleted)
    .offset(y: isEditing || isFocusing ? Self.bottomBarExitDistance : 0)
    .allowsHitTesting(!isEditing && !isFocusing)
    .accessibilityHidden(isEditing || isFocusing)
  }

  @ViewBuilder
  private var itemFocus: some View {
    if let focusedItemID, let focusedRowFrame, let participantStripFrame {
      ReceiptItemFocusView(
        draft: draft,
        itemID: focusedItemID,
        rowFrame: focusedRowFrame,
        startsPressed: isFocusedItemPressed,
        stripFrame: participantStripFrame,
        stripSelection: selectedParticipantIDs,
        amountsOwed: draft.splitCalculation.amountsOwed,
        haptic: $haptic,
        onManagePeople: { isPeoplePresented = true },
        addTransition: peopleSheetTransition,
        onDismiss: endItemFocus
      )
      // The focus view animates its own arrival, starting over the views it copies.
      .transition(.identity)
    }
  }

  private var isFocusingItem: Bool { focusedItemID != nil }

  /// Whether an item, or something on the payments page, is lifted out of its list.
  private var isFocusing: Bool { focusedItemID != nil || paymentsFocus != nil }

  private var isItemFocusPresented: Bool {
    focusedItemID != nil && focusedRowFrame != nil && participantStripFrame != nil
  }

  private var peopleSheetTransition: (id: AnyHashable, namespace: Namespace.ID) {
    (id: ReceiptReviewSheet.people, namespace: sheetTransition)
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
    return draft.merchantName.isEmpty ? "Receipt" : draft.merchantName
  }

  @ToolbarContentBuilder
  private var receiptToolbar: some ToolbarContent {
    if isEditing {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done", systemImage: "checkmark", role: .confirm, action: finishEditing)
      }
    } else if !isFocusing {
      ToolbarTitleMenu {
        Button("View & Edit Pages", systemImage: "doc.viewfinder") { isPagesPresented = true }
      }

      if !showsPayments {
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
    withAnimation(.settle) {
      isEditing = true
    }
  }

  private func focusItem(_ id: ReceiptDraftItem.ID, isPressed: Bool) {
    haptic.play(.lift)
    isFocusedItemPressed = isPressed
    withAnimation(.settle) {
      focusedItemID = id
    }
  }

  private func endItemFocus() {
    withAnimation(.settle) {
      focusedItemID = nil
      focusedRowFrame = nil
    }
  }

  private func toggleParticipantSelection(_ id: ReceiptParticipant.ID) {
    haptic.play(.selection)
    seededItemID = nil
    withAnimation(.selectionChange) {
      if selectedParticipantIDs.contains(id) {
        selectedParticipantIDs.remove(id)
      } else {
        selectedParticipantIDs.insert(id)
      }
    }
  }

  /// Extends a two-finger sweep to the item under the fingers, starting it on the first item they
  /// reach.
  private func sweepItems(at location: CGPoint) {
    guard let itemID = itemRowFrames.item(at: location) else { return }
    let updated: ReceiptItemSweep
    if var sweep {
      guard sweep.extend(to: itemID) else { return }
      updated = sweep
    } else if let started = ReceiptItemSweep(
      startingAt: itemID, in: draft.items, participantIDs: selectedParticipantIDs)
    {
      updated = started
    } else {
      return
    }
    sweep = updated
    seededItemID = nil
    haptic.play(.selection)
    withAnimation(.selectionChange) {
      draft.apply(updated)
    }
  }

  private func clearParticipantSelection() {
    haptic.play(.selection)
    seededItemID = nil
    withAnimation(.selectionChange) {
      selectedParticipantIDs = []
    }
  }

  private func removeMissingParticipantSelections() {
    let participantIDs = Set(draft.participants.map(\.id))
    seededItemID = nil
    withAnimation(.selectionChange) {
      selectedParticipantIDs.formIntersection(participantIDs)
    }
  }

  private func finishEditing() {
    draft.normalizeEditableFields()
    selectedItemID = nil
    withAnimation(.settle) {
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
