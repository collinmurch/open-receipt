import Foundation

enum ReceiptPersonResolver {
  /// The saved person `participant` is: the one it links to, else the one for its contact, so a
  /// contact deleted and saved again keeps its receipts. Participants linked to no one, as receipts
  /// split before people were saved are, fall back to a unique name.
  static func person(for participant: ReceiptParticipant, in people: [Person]) -> Person? {
    if let personID = participant.personID,
      let person = people.first(where: { $0.id == personID })
    {
      return person
    }

    if case .contact(let identifier) = participant.source,
      let contact = people.first(where: { $0.isContact(identifier) })
    {
      return contact
    }

    guard participant.personID == nil else { return nil }

    let matches = people.filter {
      $0.displayName.localizedCaseInsensitiveCompare(participant.displayName) == .orderedSame
    }
    return matches.count == 1 ? matches[0] : nil
  }
}
