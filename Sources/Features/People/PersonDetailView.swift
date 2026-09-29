import SwiftUI

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
            ContactRecipientPicker(
              contact: contact,
              selection: $selectedVenmoRecipient,
              customTitle: "Username")
          }
          if person.contactIdentifier == nil || selectedVenmoRecipient == nil {
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
            ContactRecipientPicker(
              contact: contact,
              selection: $selectedIMessageRecipient,
              customTitle: "Custom phone or email")
          }
          if person.contactIdentifier == nil || selectedIMessageRecipient == nil {
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

private protocol ContactRecipient: Hashable, Identifiable {
  static func phoneNumber(_ value: String) -> Self
  static func emailAddress(_ value: String) -> Self
  var displayValue: String { get }
}

extension Person.Venmo.Recipient: ContactRecipient {
  fileprivate static func phoneNumber(_ value: String) -> Self {
    .init(kind: .phoneNumber, value: value)
  }

  fileprivate static func emailAddress(_ value: String) -> Self {
    .init(kind: .emailAddress, value: value)
  }
}

extension Person.IMessage.Recipient: ContactRecipient {
  fileprivate static func phoneNumber(_ value: String) -> Self {
    .init(kind: .phoneNumber, value: value)
  }

  fileprivate static func emailAddress(_ value: String) -> Self {
    .init(kind: .emailAddress, value: value)
  }
}

/// A menu of the contact's phone numbers and email addresses, plus a custom entry that selects
/// `nil`.
private struct ContactRecipientPicker<Recipient: ContactRecipient>: View {
  private struct Option: Identifiable {
    let recipient: Recipient
    let title: String

    var id: Recipient.ID { recipient.id }
  }

  let contact: ContactSummary?
  @Binding var selection: Recipient?
  let customTitle: LocalizedStringKey

  var body: some View {
    let options = self.options
    LabeledContent("Recipient") {
      Menu {
        ForEach(options) { option in
          Toggle(isOn: isSelected(option.recipient)) {
            Text(option.title)
          }
        }
        Toggle(isOn: isSelected(nil)) {
          Text(customTitle)
        }
      } label: {
        if let option = options.first(where: { $0.recipient == selection }) {
          Text(option.title)
        } else {
          Text(customTitle)
        }
      }
    }
  }

  private var options: [Option] {
    let phoneNumbers = (contact?.phoneNumbers ?? []).map {
      (recipient: Recipient.phoneNumber($0.value), label: $0.label)
    }
    let emailAddresses = (contact?.emailAddresses ?? []).map {
      (recipient: Recipient.emailAddress($0.value), label: $0.label)
    }
    var options: [Option] = []
    for (recipient, label) in phoneNumbers + emailAddresses {
      guard !options.contains(where: { $0.recipient == recipient }) else { continue }
      let title = label.map { "\($0): \(recipient.displayValue)" } ?? recipient.displayValue
      options.append(Option(recipient: recipient, title: title))
    }
    if let selection, !options.contains(where: { $0.recipient == selection }) {
      options.append(Option(recipient: selection, title: selection.displayValue))
    }
    return options
  }

  private func isSelected(_ recipient: Recipient?) -> Binding<Bool> {
    Binding(
      get: { selection == recipient },
      set: { isSelected in
        if isSelected {
          selection = recipient
        }
      })
  }
}
