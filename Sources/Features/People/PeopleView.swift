import SwiftUI

struct PeopleView: View {
  @State private var model: SavedPeopleModel
  @State private var avatars = ContactAvatars()
  @State private var haptic = HapticEvent()
  @State private var pendingDeletion: Person?
  @State private var hasAdoptedContactDefaults = false
  @AppStorage(PaymentSettings.defaultMethodKey) private var defaultPaymentMethod =
    PaymentSettings.initialDefaultMethod
  @Environment(\.contactClient) private var contactClient

  init(storage: PeopleStorageClient) {
    model = SavedPeopleModel(storage: storage)
  }

  var body: some View {
    List {
      if model.isLoading {
        LoadingRow(title: "Loading people")
      } else {
        ownerSection
        peopleContent
      }
    }
    .scrollContentBackground(.hidden)
    .background { AppBackground() }
    .navigationTitle("People")
    .haptics(haptic)
    .task {
      await model.load()
      // Coming back from a person reloads them, but contacts only need checking once.
      guard !hasAdoptedContactDefaults else { return }
      hasAdoptedContactDefaults = true
      await model.adoptContactPaymentDefaults(from: contactClient)
    }
    .confirmationDialog(
      "Delete \(pendingDeletion?.displayName ?? "Person")?",
      isPresented: $pendingDeletion.isPresent,
      titleVisibility: .visible,
      presenting: pendingDeletion
    ) { person in
      Button("Delete", role: .destructive) {
        Task { await deletePerson(person) }
      }
    } message: { _ in
      Text("Existing receipts will not change. Does not remove Apple Contact.")
    }
    .errorAlert("Couldn’t Update People", message: $model.errorDescription) {
      Button("Retry") { Task { await model.load() } }
      Button("OK", role: .cancel) {}
    }
  }

  private var ownerSection: some View {
    Section {
      NavigationLink {
        OwnerContactPicker(
          contactClient: contactClient,
          selectedIdentifier: model.owner?.contactIdentifier
        ) { contact in
          Task { await model.setOwner(contact.map(ReceiptOwner.init)) }
        }
      } label: {
        let ownerName = model.owner?.displayName ?? ReceiptParticipant.defaultCurrentUserName
        HStack(spacing: 12) {
          PersonAvatarView(
            name: ownerName,
            imageData: model.owner.flatMap { avatars[$0.contactIdentifier] })
          VStack(alignment: .leading, spacing: 3) {
            Text(ownerName)
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
    model.people.filter { !$0.isContact(model.owner?.contactIdentifier) }
  }

  @ViewBuilder
  private var peopleContent: some View {
    let people = savedPeople
    if people.isEmpty {
      ContentUnavailableView(
        "No Saved People",
        systemImage: "person.2",
        description: Text("People appear here after you add them to a receipt.")
      )
      .listRowBackground(Color.clear)
    } else {
      ForEach(people) { person in
        NavigationLink {
          PersonDetailView(
            person: person,
            showsReceipts: true,
            onSave: { await model.save($0) },
            onDelete: { await deletePerson($0) })
        } label: {
          personRow(person)
        }
        .swipeActions {
          // Not destructive, which would remove the row before the deletion is confirmed.
          Button("Delete", systemImage: "trash") {
            pendingDeletion = person
          }
          .tint(.red)
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
        PaymentDestinationCaption(
          destination: person.paymentMethods.destination(globalDefault: defaultPaymentMethod))
      }
    }
    .task(id: person.contactIdentifier) {
      await loadAvatar(for: person.contactIdentifier)
    }
  }

  private func loadAvatar(for identifier: String?) async {
    guard let identifier else { return }
    _ = await avatars.avatar(for: identifier, using: contactClient)
  }

  @discardableResult
  private func deletePerson(_ person: Person) async -> Bool {
    guard await model.delete(person) else { return false }
    haptic.play(.removal)
    return true
  }
}
