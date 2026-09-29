#if !SWIFT_PACKAGE
  import Foundation
  @testable import open_receipt

  extension ReceiptDraft {
    /// Adds a person who isn’t linked to a contact.
    @discardableResult
    func addManualParticipant(named name: String) -> ReceiptParticipant {
      let date = Date(timeIntervalSince1970: 1)
      return addPerson(
        Person(
          id: UUID(),
          createdAt: date,
          updatedAt: date,
          lastIncludedAt: date,
          displayName: name,
          contactIdentifier: nil,
          paymentMethods: .init()))
    }
  }
#endif
