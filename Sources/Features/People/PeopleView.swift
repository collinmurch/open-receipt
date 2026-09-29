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
      await model.adoptContactPaymentDefaults(from: contactClient)
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
            onDelete: { await deletePerson($0) })
        } label: {
          personRow(person)
        }
        .swipeActions {
          Button("Delete", systemImage: "trash", role: .destructive) {
            Task { await deletePerson(person) }
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
      contactClient.authorizationStatus().canReadContacts,
      let avatar = try? await contactClient.fetchAvatar(identifier)
    else { return }
    avatars[identifier] = avatar
  }

  private var defaultPaymentMethod: PaymentMethod {
    PaymentMethod(rawValue: defaultPaymentMethodRawValue)
      ?? PaymentSettings.initialDefaultMethod
  }

  @discardableResult
  private func deletePerson(_ person: Person) async -> Bool {
    guard await model.delete(person) else { return false }
    haptic.play(.removal)
    return true
  }
}
