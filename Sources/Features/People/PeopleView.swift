import SwiftUI

struct PeopleView: View {
  @State private var model: SavedPeopleModel
  @State private var avatars: [String: Data] = [:]
  @State private var haptic = HapticEvent()
  @AppStorage(PaymentSettings.defaultMethodKey) private var defaultPaymentMethodRawValue =
    PaymentSettings.initialDefaultMethod.rawValue
  @Environment(\.contactClient) private var contactClient
  private let receiptStorage: ReceiptStorageClient

  init(storage: PeopleStorageClient, receiptStorage: ReceiptStorageClient) {
    model = SavedPeopleModel(storage: storage)
    self.receiptStorage = receiptStorage
  }

  var body: some View {
    List {
      if model.isLoading {
        HStack {
          Spacer()
          ProgressView("Loading people")
          Spacer()
        }
      } else {
        ownerSection
        peopleContent
      }
    }
    .navigationTitle("People")
    .haptics(haptic)
    .errorHaptic(model.errorDescription)
    .task {
      await model.load(receiptStorage: receiptStorage)
      await addDefaultPaymentMethods()
    }
    .alert(
      "Couldn’t Update People",
      isPresented: Binding(
        get: { model.errorDescription != nil },
        set: { if !$0 { model.errorDescription = nil } })
    ) {
      Button("Retry") { Task { await model.load(receiptStorage: receiptStorage) } }
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.errorDescription ?? "The people list could not be updated.")
    }
  }

  private var ownerSection: some View {
    Section {
      NavigationLink {
        OwnerContactPicker(
          contactClient: contactClient,
          selectedIdentifier: model.owner?.contactIdentifier
        ) { contact in
          Task {
            if await model.setOwner(contact.map(ReceiptOwner.init)) {
              haptic.play(.selection)
            }
          }
        }
      } label: {
        HStack(spacing: 12) {
          PersonAvatarView(
            name: model.owner?.displayName ?? ReceiptParticipant.defaultCurrentUserName,
            imageData: model.owner.flatMap { avatars[$0.contactIdentifier] })
          VStack(alignment: .leading, spacing: 3) {
            Text(model.owner?.displayName ?? ReceiptParticipant.defaultCurrentUserName)
            Text(model.owner == nil ? "Choose your contact" : "You")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .task(id: model.owner?.contactIdentifier) {
          await loadAvatar(for: model.owner?.contactIdentifier)
        }
      }
    } footer: {
      Text("New receipts start with this contact as you.")
    }
  }

  private var savedPeople: [Person] {
    model.people.filter {
      $0.contactIdentifier == nil || $0.contactIdentifier != model.owner?.contactIdentifier
    }
  }

  @ViewBuilder
  private var peopleContent: some View {
    if savedPeople.isEmpty {
      ContentUnavailableView(
        "No Saved People",
        systemImage: "person.2",
        description: Text("People appear here after you add them to a receipt."))
    } else {
      ForEach(savedPeople) { person in
        NavigationLink {
          PersonDetailView(
            person: person,
            onSave: { await model.save($0) },
            onDelete: { await model.delete($0) })
        } label: {
          personRow(person)
        }
        .swipeActions {
          Button("Delete", systemImage: "trash", role: .destructive) {
            Task {
              if await model.delete(person) {
                haptic.play(.removal)
              }
            }
          }
        }
      }
    }
  }

  private func personRow(_ person: Person) -> some View {
    HStack(spacing: 12) {
      PersonAvatarView(
        name: person.displayName,
        imageData: person.contactIdentifier.flatMap { avatars[$0] })
      VStack(alignment: .leading, spacing: 3) {
        Text(person.displayName)
        if let destination = person.paymentMethods.destination(
          globalDefault: defaultPaymentMethod)
        {
          Text("\(destination.method.title) \(destination.displayValue)")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("No payment method set")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
    }
    .task(id: person.contactIdentifier) {
      await loadAvatar(for: person.contactIdentifier)
    }
  }

  private func loadAvatar(for identifier: String?) async {
    guard let identifier,
      contactClient.authorizationStatus() == .authorized
        || contactClient.authorizationStatus() == .limited,
      let avatar = try? await contactClient.fetchAvatar(identifier)
    else { return }
    avatars[identifier] = avatar
  }

  private var defaultPaymentMethod: PaymentMethod {
    PaymentMethod(rawValue: defaultPaymentMethodRawValue)
      ?? PaymentSettings.initialDefaultMethod
  }

  private func addDefaultPaymentMethods() async {
    let defaults = await contactClient.defaultPaymentMethods(for: model.people)
    for person in model.people {
      guard let paymentDefaults = defaults[person.id] else { continue }
      var updated = person
      var didChange = false
      if let recipient = paymentDefaults.venmo {
        updated.paymentMethods.venmo = .init(recipient: recipient)
        didChange = true
      }
      if let recipient = paymentDefaults.iMessage {
        updated.paymentMethods.iMessage = .init(recipient: recipient)
        didChange = true
      }
      if didChange {
        _ = await model.save(updated)
      }
    }
  }
}

struct PersonDetailView: View {
  let onSave: (Person) async -> Person?
  let onDelete: (Person) async -> Bool
  @State private var person: Person
  @State private var selectedVenmoRecipient: Person.Venmo.Recipient?
  @State private var customVenmoUsername: String
  @State private var cashAppCashtag: String
  @State private var selectedIMessageRecipient: Person.IMessage.Recipient?
  @State private var customIMessageRecipient: String
  @State private var contact: ContactSummary?
  @State private var avatarData: Data?
  @State private var isDeleteConfirmationPresented = false
  @State private var isDeleting = false
  @State private var isAppleContactPresented = false
  @State private var haptic = HapticEvent()
  @AppStorage(PaymentSettings.defaultMethodKey) private var globalDefaultMethodRawValue =
    PaymentSettings.initialDefaultMethod.rawValue
  @Environment(\.contactClient) private var contactClient
  @Environment(\.dismiss) private var dismiss

  init(
    person: Person,
    onSave: @escaping (Person) async -> Person?,
    onDelete: @escaping (Person) async -> Bool
  ) {
    self.onSave = onSave
    self.onDelete = onDelete
    _person = State(initialValue: person)
    let venmo = person.paymentMethods.venmo
    _selectedVenmoRecipient = State(
      initialValue: venmo?.recipient.kind == .username ? nil : venmo?.recipient)
    let initialCustomUsername: String
    if let venmo {
      initialCustomUsername =
        venmo.customUsername
        ?? (venmo.recipient.kind == .username ? venmo.recipient.value : "")
    } else {
      initialCustomUsername = ""
    }
    _customVenmoUsername = State(
      initialValue: initialCustomUsername)
    _cashAppCashtag = State(initialValue: person.paymentMethods.cashApp?.cashtag ?? "")
    let iMessage = person.paymentMethods.iMessage
    _selectedIMessageRecipient = State(
      initialValue: iMessage?.recipient.kind == .custom ? nil : iMessage?.recipient)
    _customIMessageRecipient = State(
      initialValue: iMessage?.recipient.kind == .custom ? iMessage?.recipient.value ?? "" : "")
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
          TextField("Name", text: $person.displayName)
            .textContentType(.name)
            .multilineTextAlignment(.trailing)
        }
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

        DisclosureGroup {
          if person.contactIdentifier != nil {
            LabeledContent("Recipient") {
              Menu {
                ForEach(availableVenmoRecipients) { recipient in
                  Toggle(
                    isOn: Binding(
                      get: { selectedVenmoRecipient == recipient },
                      set: { isSelected in
                        if isSelected {
                          selectedVenmoRecipient = recipient
                        }
                      })
                  ) {
                    Text(venmoRecipientLabel(recipient))
                  }
                }
                Toggle(
                  isOn: Binding(
                    get: { selectedVenmoRecipient == nil },
                    set: { isSelected in
                      if isSelected {
                        selectedVenmoRecipient = nil
                      }
                    })
                ) {
                  Text("Username")
                }
              } label: {
                Text(
                  selectedVenmoRecipient.map(venmoRecipientLabel) ?? "Username")
              }
            }

            if selectedVenmoRecipient == nil {
              customUsernameField
            }
          } else {
            customUsernameField
          }
        } label: {
          paymentMethodDisclosureLabel(.venmo)
        }

        DisclosureGroup {
          cashAppField
        } label: {
          paymentMethodDisclosureLabel(.cashApp)
        }

        DisclosureGroup {
          if person.contactIdentifier != nil {
            LabeledContent("Recipient") {
              Menu {
                ForEach(availableIMessageRecipients) { recipient in
                  Toggle(
                    isOn: Binding(
                      get: { selectedIMessageRecipient == recipient },
                      set: { isSelected in
                        if isSelected {
                          selectedIMessageRecipient = recipient
                        }
                      })
                  ) {
                    Text(iMessageRecipientLabel(recipient))
                  }
                }
                Toggle(
                  isOn: Binding(
                    get: { selectedIMessageRecipient == nil },
                    set: { isSelected in
                      if isSelected {
                        selectedIMessageRecipient = nil
                      }
                    })
                ) {
                  Text("Custom phone or email")
                }
              } label: {
                Text(
                  selectedIMessageRecipient.map(iMessageRecipientLabel)
                    ?? "Custom phone or email")
              }
            }

            if selectedIMessageRecipient == nil {
              customIMessageField
            }
          } else {
            customIMessageField
          }
        } label: {
          paymentMethodDisclosureLabel(.iMessage)
        }
      }
    }
    .navigationTitle(person.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .principal) {
        Text(person.displayName)
          .font(.headline)
      }

      ToolbarItem(placement: .confirmationAction) {
        Button(role: .destructive) {
          isDeleteConfirmationPresented = true
        } label: {
          Image(systemName: "trash")
            .font(.subheadline)
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete Person")
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
            haptic.play(.removal)
            dismiss()
          } else {
            isDeleting = false
          }
        }
      }
    } message: {
      Text("Existing receipts will not change. Does not remove Apple Contact.")
    }
    .haptics(haptic)
    .task(id: person.contactIdentifier) {
      await loadContact()
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
    LabeledContent("Username") {
      HStack(spacing: 2) {
        Text("@")
          .foregroundStyle(.secondary)
        TextField("username", text: $customVenmoUsername)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .multilineTextAlignment(.trailing)
          .fixedSize(horizontal: true, vertical: false)
      }
      .fixedSize(horizontal: true, vertical: false)
    }
  }

  private var cashAppField: some View {
    LabeledContent("Cashtag") {
      HStack(spacing: 2) {
        Text("$")
          .foregroundStyle(.secondary)
        TextField("cashtag", text: $cashAppCashtag)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .multilineTextAlignment(.trailing)
          .fixedSize(horizontal: true, vertical: false)
      }
      .fixedSize(horizontal: true, vertical: false)
    }
  }

  private var customIMessageField: some View {
    LabeledContent("Phone or Email") {
      TextField("Phone or email", text: $customIMessageRecipient)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .multilineTextAlignment(.trailing)
    }
  }

  private var defaultPaymentMethodRow: some View {
    let isSelected = person.paymentMethods.defaultMethod == nil
    let globalDefault =
      PaymentMethod(rawValue: globalDefaultMethodRawValue) ?? PaymentSettings.initialDefaultMethod
    return Button {
      selectDefaultMethod(nil)
    } label: {
      HStack {
        selectionIndicator(isSelected: isSelected)
        Text("Default")
        Text("(\(globalDefault.title))")
          .foregroundStyle(.secondary)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Default (\(globalDefault.title))")
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

  private func selectDefaultMethod(_ method: PaymentMethod?) {
    guard person.paymentMethods.defaultMethod != method else { return }
    person.paymentMethods.defaultMethod = method
    haptic.play(.selection)
  }

  private func selectionIndicator(isSelected: Bool) -> some View {
    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
      .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
  }

  private var availableVenmoRecipients: [Person.Venmo.Recipient] {
    var recipients =
      (contact?.phoneNumbers ?? []).map {
        Person.Venmo.Recipient(kind: .phoneNumber, value: $0.value)
      }
      + (contact?.emailAddresses ?? []).map {
        Person.Venmo.Recipient(kind: .emailAddress, value: $0.value)
      }
    if let selectedVenmoRecipient, !recipients.contains(selectedVenmoRecipient) {
      recipients.append(selectedVenmoRecipient)
    }
    return recipients.reduce(into: []) { result, recipient in
      guard !result.contains(recipient) else { return }
      result.append(recipient)
    }
  }

  private var availableIMessageRecipients: [Person.IMessage.Recipient] {
    var recipients =
      (contact?.phoneNumbers ?? []).map {
        Person.IMessage.Recipient(kind: .phoneNumber, value: $0.value)
      }
      + (contact?.emailAddresses ?? []).map {
        Person.IMessage.Recipient(kind: .emailAddress, value: $0.value)
      }
    if let selectedIMessageRecipient, !recipients.contains(selectedIMessageRecipient) {
      recipients.append(selectedIMessageRecipient)
    }
    return recipients.reduce(into: []) { result, recipient in
      guard !result.contains(recipient) else { return }
      result.append(recipient)
    }
  }

  private func venmoRecipientLabel(_ recipient: Person.Venmo.Recipient) -> String {
    let values: [ContactSummary.Value]
    switch recipient.kind {
    case .phoneNumber:
      values = contact?.phoneNumbers ?? []
    case .emailAddress:
      values = contact?.emailAddresses ?? []
    case .username:
      return recipient.displayValue
    }
    guard let label = values.first(where: { $0.value == recipient.value })?.label else {
      return recipient.displayValue
    }
    return "\(label): \(recipient.displayValue)"
  }

  private func iMessageRecipientLabel(_ recipient: Person.IMessage.Recipient) -> String {
    let values: [ContactSummary.Value]
    switch recipient.kind {
    case .phoneNumber:
      values = contact?.phoneNumbers ?? []
    case .emailAddress:
      values = contact?.emailAddresses ?? []
    case .custom:
      return recipient.displayValue
    }
    guard let label = values.first(where: { $0.value == recipient.value })?.label else {
      return recipient.displayValue
    }
    return "\(label): \(recipient.displayValue)"
  }

  private func loadContact() async {
    guard let identifier = person.contactIdentifier,
      contactClient.authorizationStatus() == .authorized
        || contactClient.authorizationStatus() == .limited
    else { return }
    avatarData = try? await contactClient.fetchAvatar(identifier)
    guard let loadedContact = try? await contactClient.fetchContacts([identifier]).first
    else { return }
    contact = loadedContact
    if person.paymentMethods.venmo == nil,
      selectedVenmoRecipient == nil,
      normalizedUsername(customVenmoUsername).isEmpty
    {
      selectedVenmoRecipient = loadedContact.defaultVenmoRecipient
    }
    if person.paymentMethods.iMessage == nil,
      selectedIMessageRecipient == nil,
      normalizedValue(customIMessageRecipient).isEmpty
    {
      selectedIMessageRecipient = loadedContact.defaultIMessageRecipient
    }
  }

  private func saveChanges() {
    guard !isDeleting else { return }
    var updatedPerson = person
    updatedPerson.displayName = person.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !updatedPerson.displayName.isEmpty else { return }
    let username = normalizedUsername(customVenmoUsername)
    if let selectedVenmoRecipient {
      updatedPerson.paymentMethods.venmo = .init(
        recipient: selectedVenmoRecipient,
        customUsername: username.isEmpty ? nil : username)
    } else {
      updatedPerson.paymentMethods.venmo = username.isEmpty ? nil : .init(username: username)
    }
    let cashtag = normalizedCashtag(cashAppCashtag)
    updatedPerson.paymentMethods.cashApp =
      cashtag.isEmpty ? nil : .init(cashtag: cashtag)
    if let selectedIMessageRecipient {
      updatedPerson.paymentMethods.iMessage = .init(recipient: selectedIMessageRecipient)
    } else {
      let recipient = normalizedValue(customIMessageRecipient)
      updatedPerson.paymentMethods.iMessage =
        recipient.isEmpty
        ? nil
        : .init(recipient: .init(kind: .custom, value: recipient))
    }
    Task {
      _ = await onSave(updatedPerson)
    }
  }

  private func normalizedUsername(_ username: String) -> String {
    String(
      username.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingPrefix("@"))
  }

  private func normalizedCashtag(_ cashtag: String) -> String {
    Person.CashApp.normalizedCashtag(cashtag)
  }

  private func normalizedValue(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
