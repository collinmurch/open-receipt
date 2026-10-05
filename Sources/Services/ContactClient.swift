import Contacts
import SwiftUI

enum ContactAuthorization: Sendable, Equatable {
  case notDetermined
  case restricted
  case denied
  case limited
  case authorized

  var canReadContacts: Bool {
    self == .limited || self == .authorized
  }

  init(_ status: CNAuthorizationStatus) {
    switch status {
    case .notDetermined:
      self = .notDetermined
    case .restricted:
      self = .restricted
    case .denied:
      self = .denied
    case .limited:
      self = .limited
    case .authorized:
      self = .authorized
    @unknown default:
      self = .denied
    }
  }
}

struct ContactClient: Sendable {
  var authorizationStatus: @Sendable () -> ContactAuthorization
  var requestAccess: @Sendable () async throws -> ContactAuthorization
  var fetchContacts: @Sendable ([String]?) async throws -> [ContactSummary]
  var fetchAvatar: @Sendable (String) async throws -> Data?

  static let live = ContactClient(
    authorizationStatus: {
      ContactAuthorization(CNContactStore.authorizationStatus(for: .contacts))
    },
    requestAccess: {
      try await LiveContactStore.shared.requestAccess()
    },
    fetchContacts: { identifiers in
      try await LiveContactStore.shared.fetchContacts(identifiers: identifiers)
    },
    fetchAvatar: { identifier in
      try await LiveContactStore.shared.fetchAvatar(identifier: identifier)
    })

  func defaultPaymentMethods(
    for people: [Person]
  ) async -> [Person.ID: ContactPaymentDefaults] {
    let eligiblePeople = people.filter {
      ($0.paymentMethods.venmo == nil || $0.paymentMethods.iMessage == nil)
        && $0.contactIdentifier != nil
    }
    let identifiers = eligiblePeople.compactMap(\.contactIdentifier)
    guard !identifiers.isEmpty,
      authorizationStatus().canReadContacts,
      let contacts = try? await fetchContacts(identifiers)
    else { return [:] }
    let contactsByIdentifier = Dictionary(
      uniqueKeysWithValues: contacts.map { ($0.identifier, $0) })
    return Dictionary(
      uniqueKeysWithValues: eligiblePeople.compactMap { person in
        guard let identifier = person.contactIdentifier,
          let contact = contactsByIdentifier[identifier]
        else { return nil }
        return (person.id, contact.paymentDefaults(for: person))
      })
  }
}

private actor LiveContactStore {
  static let shared = LiveContactStore()

  private let store = CNContactStore()

  func requestAccess() async throws -> ContactAuthorization {
    _ = try await store.requestAccess(for: .contacts)
    return ContactAuthorization(CNContactStore.authorizationStatus(for: .contacts))
  }

  func fetchContacts(identifiers: [String]?) throws -> [ContactSummary] {
    let keys = [
      CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
      CNContactPhoneNumbersKey as CNKeyDescriptor,
      CNContactEmailAddressesKey as CNKeyDescriptor,
    ]
    let contacts: [CNContact]

    if let identifiers {
      guard !identifiers.isEmpty else { return [] }
      let predicate = CNContact.predicateForContacts(withIdentifiers: identifiers)
      contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
    } else {
      let request = CNContactFetchRequest(keysToFetch: keys)
      request.sortOrder = .userDefault
      var fetchedContacts: [CNContact] = []
      try store.enumerateContacts(with: request) { contact, _ in
        fetchedContacts.append(contact)
      }
      contacts = fetchedContacts
    }

    return
      contacts
      .map { contact in
        ContactSummary(
          identifier: contact.identifier,
          displayName: CNContactFormatter.string(from: contact, style: .fullName)
            ?? "Unnamed Contact",
          phoneNumbers: contact.phoneNumbers.map {
            .init(label: Self.localizedLabel($0.label), value: $0.value.stringValue)
          },
          emailAddresses: contact.emailAddresses.map {
            .init(label: Self.localizedLabel($0.label), value: $0.value as String)
          })
      }
      .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
  }

  private static func localizedLabel(_ label: String?) -> String? {
    guard let label else { return nil }
    return CNLabeledValue<NSString>.localizedString(forLabel: label)
  }

  func fetchAvatar(identifier: String) throws -> Data? {
    let contact = try store.unifiedContact(
      withIdentifier: identifier,
      keysToFetch: [CNContactThumbnailImageDataKey as CNKeyDescriptor])
    return contact.thumbnailImageData
  }
}

extension EnvironmentValues {
  @Entry var contactClient = ContactClient.live
}
