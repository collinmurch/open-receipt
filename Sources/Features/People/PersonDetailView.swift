import SwiftUI

struct PersonDetailView: View {
  private enum Field: Hashable {
    case name
    case venmoUsername
    case cashtag
    case iMessageRecipient
  }

  /// Whether the receipts this person is on are listed and can be opened. Left off where the
  /// person is shown from inside a receipt, so receipts and people can't open each other without
  /// end.
  let showsReceipts: Bool
  let onSave: (Person) async -> Void
  let onDelete: (Person) async -> Bool
  private let savedPerson: Person
  /// What was last saved, so leaving for a receipt and then leaving the screen saves only once.
  @State private var lastSavedPerson: Person
  @State private var person: Person
  @State private var paymentMethods: PaymentMethodsDraft
  @State private var contact: ContactSummary?
  @State private var avatarData: Data?
  @State private var isDeleteConfirmationPresented = false
  @State private var isDeleting = false
  @State private var isAppleContactPresented = false
  @State private var expandedMethod: PaymentMethod?
  @State private var receipts: [PersonReceipt] = []
  @FocusState private var focusedField: Field?
  @AppStorage(PaymentSettings.defaultMethodKey) private var globalDefaultMethod =
    PaymentSettings.initialDefaultMethod
  @Environment(\.contactClient) private var contactClient
  @Environment(\.receiptStorageClient) private var receiptStorage
  @Environment(\.peopleStorageClient) private var peopleStorage
  @Environment(ReceiptLibraryModel.self) private var library
  @Environment(ReceiptRecognitionCenter.self) private var recognitions
  @Environment(\.dismiss) private var dismiss

  init(
    person: Person,
    showsReceipts: Bool,
    onSave: @escaping (Person) async -> Void,
    onDelete: @escaping (Person) async -> Bool
  ) {
    self.showsReceipts = showsReceipts
    self.onSave = onSave
    self.onDelete = onDelete
    savedPerson = person
    _lastSavedPerson = State(initialValue: person)
    _person = State(initialValue: person)
    _paymentMethods = State(initialValue: PaymentMethodsDraft(person.paymentMethods))
  }

  var body: some View {
    Form {
      if let avatarData {
        HStack {
          Spacer()
          PersonAvatarView(name: person.displayName, imageData: avatarData, size: 112)
          Spacer()
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
      }

      Section("Person") {
        LabeledContent("Name") {
          FormTextField("Name", text: $person.displayName)
            .textContentType(.name)
            .focused($focusedField, equals: .name)
        }
        .focusesOnTap($focusedField, equals: .name)
        if person.contactIdentifier != nil {
          LabeledContent("Source") {
            Button("Apple Contacts") {
              isAppleContactPresented = true
            }
          }
        }
      }

      Section("Payment Methods") {
        defaultPaymentMethodRow

        DisclosureGroup(isExpanded: isExpanded(.venmo)) {
          if person.contactIdentifier != nil {
            ContactRecipientPicker(
              contact: contact,
              selection: $paymentMethods.venmoRecipient,
              customTitle: "Username")
          }
          if person.contactIdentifier == nil || paymentMethods.venmoRecipient == nil {
            customUsernameField
          }
        } label: {
          paymentMethodDisclosureLabel(.venmo)
        }

        DisclosureGroup(isExpanded: isExpanded(.cashApp)) {
          cashAppField
        } label: {
          paymentMethodDisclosureLabel(.cashApp)
        }

        DisclosureGroup(isExpanded: isExpanded(.iMessage)) {
          if person.contactIdentifier != nil {
            ContactRecipientPicker(
              contact: contact,
              selection: $paymentMethods.iMessageRecipient,
              customTitle: "Custom phone or email")
          }
          if person.contactIdentifier == nil || paymentMethods.iMessageRecipient == nil {
            customIMessageField
          }
        } label: {
          paymentMethodDisclosureLabel(.iMessage)
        }
      }

      if !receipts.isEmpty {
        Section("Receipts") {
          ForEach(receipts) { receipt in
            NavigationLink {
              PersonReceiptDestination(input: flowInput(for: receipt))
            } label: {
              PersonReceiptRow(receipt: receipt)
            }
          }
        }
      }
    }
    .navigationTitle(person.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .dismissesKeyboardOnTap()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Delete Person", systemImage: "trash", role: .destructive) {
          isDeleteConfirmationPresented = true
        }
      }
    }
    .confirmationDialog(
      "Delete \(person.displayName)?",
      isPresented: $isDeleteConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        Task {
          isDeleting = true
          if await onDelete(person) {
            dismiss()
          } else {
            isDeleting = false
          }
        }
      }
    } message: {
      Text("Existing receipts will not change. Does not remove Apple Contact.")
    }
    .task(id: person.contactIdentifier) {
      await loadContact()
    }
    .task(id: showsReceipts ? library.receipts : nil) {
      await loadReceipts()
    }
    .sheet(isPresented: $isAppleContactPresented) {
      if let identifier = person.contactIdentifier {
        AppleContactView(identifier: identifier) {
          isAppleContactPresented = false
        }
        .ignoresSafeArea(.container, edges: .bottom)
      }
    }
    .onDisappear {
      saveChanges()
    }
  }

  private var customUsernameField: some View {
    handleField(
      "Username", prefix: "@", placeholder: "username", text: $paymentMethods.venmoUsername,
      field: .venmoUsername)
  }

  private var cashAppField: some View {
    handleField(
      "Cashtag", prefix: "$", placeholder: "cashtag", text: $paymentMethods.cashtag,
      field: .cashtag)
  }

  /// A username field that shows the service's `prefix` before what's typed.
  private func handleField(
    _ title: LocalizedStringKey,
    prefix: String,
    placeholder: String,
    text: Binding<String>,
    field: Field
  ) -> some View {
    LabeledContent(title) {
      HStack(spacing: 2) {
        Text(prefix)
          .foregroundStyle(.secondary)
        FormTextField(placeholder, text: text)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($focusedField, equals: field)
          .fixedSize(horizontal: true, vertical: false)
      }
      .fixedSize(horizontal: true, vertical: false)
    }
    .focusesOnTap($focusedField, equals: field)
  }

  private var customIMessageField: some View {
    LabeledContent("Phone or Email") {
      FormTextField("Phone or email", text: $paymentMethods.customIMessageRecipient)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($focusedField, equals: .iMessageRecipient)
    }
    .focusesOnTap($focusedField, equals: .iMessageRecipient)
  }

  private var defaultPaymentMethodRow: some View {
    let isSelected = person.paymentMethods.defaultMethod == nil
    return Button {
      selectDefaultMethod(nil)
    } label: {
      HStack {
        selectionIndicator(isSelected: isSelected)
        Text("Default")
        Text("(\(globalDefaultMethod.title))")
          .foregroundStyle(.secondary)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Default (\(globalDefaultMethod.title))")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func paymentMethodDisclosureLabel(_ method: PaymentMethod) -> some View {
    let isSelected = person.paymentMethods.defaultMethod == method
    return HStack {
      Button {
        selectDefaultMethod(method)
      } label: {
        selectionIndicator(isSelected: isSelected)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Select \(method.title)")
      .accessibilityAddTraits(isSelected ? .isSelected : [])

      PaymentMethodIcon(method: method)
      Text(method.title)
    }
  }

  /// Expands one payment method at a time, collapsing the one open before it.
  private func isExpanded(_ method: PaymentMethod) -> Binding<Bool> {
    Binding(
      get: { expandedMethod == method },
      set: { isExpanded in
        if isExpanded {
          expandedMethod = method
        } else if expandedMethod == method {
          expandedMethod = nil
        }
      })
  }

  /// Makes `method` the default and expands it so its details can be filled in.
  private func selectDefaultMethod(_ method: PaymentMethod?) {
    withAnimation(.smooth(duration: 0.3)) { expandedMethod = method }
    guard person.paymentMethods.defaultMethod != method else { return }
    person.paymentMethods.defaultMethod = method
  }

  private func selectionIndicator(isSelected: Bool) -> some View {
    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
      .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
      .contentTransition(.symbolEffect(.replace))
      .animation(.smooth(duration: 0.2), value: isSelected)
  }

  private func loadContact() async {
    guard let identifier = person.contactIdentifier,
      contactClient.authorizationStatus().canReadContacts
    else { return }
    avatarData = try? await contactClient.fetchAvatar(identifier)
    guard let loadedContact = try? await contactClient.fetchContacts([identifier]).first
    else { return }
    contact = loadedContact
    paymentMethods.suggest(from: loadedContact, unlessSetIn: person.paymentMethods)
  }

  /// Reloads whenever the library does, so edits made in an opened receipt show on return.
  private func loadReceipts() async {
    guard showsReceipts else { return }
    let people = (try? await peopleStorage.list()) ?? [savedPerson]
    let loaded = await PersonReceipt.load(
      for: savedPerson,
      in: library.receipts,
      people: people,
      storage: receiptStorage)
    guard !Task.isCancelled else { return }
    withAnimation(.smooth(duration: 0.3)) { receipts = loaded }
  }

  private func flowInput(for receipt: PersonReceipt) -> ReceiptFlowInput {
    if let recognition = recognitions.recognition(for: receipt.id) {
      return .recognition(recognition)
    }
    return .storedReceipt(
      receipt.id,
      backgroundStyle: receipt.summary.backgroundStyle,
      document: receipt.document)
  }

  /// Saves the edited person, unless nothing changed or the name was cleared.
  private func saveChanges() {
    guard !isDeleting else { return }
    var updatedPerson = person
    updatedPerson.displayName = person.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !updatedPerson.displayName.isEmpty else { return }
    paymentMethods.apply(to: &updatedPerson.paymentMethods)
    guard updatedPerson != lastSavedPerson else { return }
    lastSavedPerson = updatedPerson
    Task {
      await onSave(updatedPerson)
    }
  }
}
