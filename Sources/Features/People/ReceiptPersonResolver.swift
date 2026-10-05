import Foundation

enum ReceiptPersonResolver {
  static func person(for participant: ReceiptParticipant, in people: [Person]) -> Person? {
    if let personID = participant.personID {
      return people.first { $0.id == personID }
    }

    if case .contact(let identifier) = participant.source,
      let contact = people.first(where: { $0.contactIdentifier == identifier })
    {
      return contact
    }

    let matches = people.filter {
      $0.displayName.localizedCaseInsensitiveCompare(participant.displayName) == .orderedSame
    }
    return matches.count == 1 ? matches[0] : nil
  }
}
