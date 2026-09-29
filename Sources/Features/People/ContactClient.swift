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
}

struct ContactSummary: Identifiable, Sendable, Equatable {
  struct Value: Identifiable, Sendable, Equatable, Hashable {
    var id: String { "\(label ?? ""):\(value)" }

    let label: String?
    let value: String
  }

  var id: String { identifier }

  let identifier: String
  let displayName: String
  let phoneNumbers: [Value]
  let emailAddresses: [Value]

  init(
    identifier: String,
    displayName: String,
    phoneNumbers: [Value] = [],
    emailAddresses: [Value] = []
  ) {
    self.identifier = identifier
    self.displayName = displayName
    self.phoneNumbers = Self.deduplicatedPhoneNumbers(phoneNumbers)
    self.emailAddresses = emailAddresses
  }

  private static func deduplicatedPhoneNumbers(_ phoneNumbers: [Value]) -> [Value] {
    var result: [Value] = []
    var indicesByNumber: [String: Int] = [:]

    for phoneNumber in phoneNumbers {
      let value = Value(
        label: normalizedPhoneLabel(phoneNumber.label),
        value: phoneNumber.value)
      let key = normalizedPhoneNumber(value.value)
      guard let index = indicesByNumber[key] else {
        indicesByNumber[key] = result.count
        result.append(value)
        continue
      }
      if isMobileLabel(value.label), !isMobileLabel(result[index].label) {
        result[index] = value
      }
    }
    return result
  }

  private static func normalizedPhoneLabel(_ label: String?) -> String? {
    guard let label else { return nil }
    return label.caseInsensitiveCompare("iPhone") == .orderedSame
      ? CNLabeledValue<NSString>.localizedString(forLabel: CNLabelPhoneNumberMobile)
      : label
  }

  private static func normalizedPhoneNumber(_ value: String) -> String {
    let digits = String(value.unicodeScalars.filter { (48...57).contains($0.value) })
    guard !digits.isEmpty else { return value.lowercased() }
    return digits.count == 11 && digits.hasPrefix("1") ? String(digits.dropFirst()) : digits
  }

  private static func isMobileLabel(_ label: String?) -> Bool {
    guard let label else { return false }
    let mobileLabel = CNLabeledValue<NSString>.localizedString(forLabel: CNLabelPhoneNumberMobile)
    return label.caseInsensitiveCompare("mobile") == .orderedSame
      || label.caseInsensitiveCompare("iPhone") == .orderedSame
      || label.caseInsensitiveCompare(mobileLabel) == .orderedSame
  }

  var defaultVenmoRecipient: Person.Venmo.Recipient? {
    if let phoneNumber = phoneNumbers.first {
      return .init(kind: .phoneNumber, value: phoneNumber.value)
    }
    if let emailAddress = emailAddresses.first {
      return .init(kind: .emailAddress, value: emailAddress.value)
    }
    return nil
  }

  var defaultIMessageRecipient: Person.IMessage.Recipient? {
    if let phoneNumber = phoneNumbers.first {
      return .init(kind: .phoneNumber, value: phoneNumber.value)
    }
    if let emailAddress = emailAddresses.first {
      return .init(kind: .emailAddress, value: emailAddress.value)
    }
    return nil
  }

  /// The payment methods this contact suggests for those `person` hasn't set.
  func paymentDefaults(for person: Person) -> ContactPaymentDefaults {
    ContactPaymentDefaults(
      venmo: person.paymentMethods.venmo == nil ? defaultVenmoRecipient : nil,
      iMessage: person.paymentMethods.iMessage == nil ? defaultIMessageRecipient : nil)
  }
}

struct ContactPaymentDefaults: Sendable, Equatable {
  let venmo: Person.Venmo.Recipient?
  let iMessage: Person.IMessage.Recipient?
}

extension Person {
  /// Fills in the payment methods suggested by the person's contact, returning whether any changed.
  mutating func adopt(_ defaults: ContactPaymentDefaults) -> Bool {
    var didChange = false
    if let recipient = defaults.venmo {
      paymentMethods.venmo = .init(recipient: recipient)
      didChange = true
    }
    if let recipient = defaults.iMessage {
      paymentMethods.iMessage = .init(recipient: recipient)
      didChange = true
    }
    return didChange
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

extension ContactAuthorization {
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

private struct ContactClientKey: EnvironmentKey {
  static let defaultValue = ContactClient.live
}

extension EnvironmentValues {
  var contactClient: ContactClient {
    get { self[ContactClientKey.self] }
    set { self[ContactClientKey.self] = newValue }
  }
}
