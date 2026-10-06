import XCTest

@testable import open_receipt

final class PaymentMethodsDraftTests: XCTestCase {
  func testUneditedDraftAppliesSavedMethods() {
    let saved = Person.PaymentMethods(
      defaultMethod: .cashApp,
      venmo: .init(username: "sam"),
      cashApp: .init(cashtag: "sam"),
      iMessage: .init(recipient: .init(kind: .custom, value: "sam@example.com")))
    var methods = saved

    PaymentMethodsDraft(saved).apply(to: &methods)

    XCTAssertEqual(methods, saved)
  }

  func testBlankFieldsRemoveMethods() {
    var methods = Person.PaymentMethods(
      venmo: .init(username: "sam"),
      cashApp: .init(cashtag: "sam"),
      iMessage: .init(recipient: .init(kind: .custom, value: "sam@example.com")))
    var draft = PaymentMethodsDraft(methods)
    draft.venmoUsername = ""
    draft.cashtag = " "
    draft.customIMessageRecipient = "\n"

    draft.apply(to: &methods)

    XCTAssertNil(methods.venmo)
    XCTAssertNil(methods.cashApp)
    XCTAssertNil(methods.iMessage)
  }

  func testContactRecipientKeepsTypedUsername() {
    var methods = Person.PaymentMethods()
    var draft = PaymentMethodsDraft(methods)
    draft.venmoRecipient = .phoneNumber("5551234567")
    draft.venmoUsername = "sam"

    draft.apply(to: &methods)

    XCTAssertEqual(
      methods.venmo, .init(recipient: .phoneNumber("5551234567"), customUsername: "sam"))
  }

  func testSuggestPicksContactRecipients() {
    var draft = PaymentMethodsDraft(Person.PaymentMethods())

    draft.suggest(from: contact, unlessSetIn: Person.PaymentMethods())

    XCTAssertEqual(draft.venmoRecipient, .phoneNumber("5551234567"))
    XCTAssertEqual(draft.iMessageRecipient, .phoneNumber("5551234567"))
  }

  func testSuggestKeepsWhatWasTyped() {
    var draft = PaymentMethodsDraft(Person.PaymentMethods())
    draft.venmoUsername = "sam"
    draft.customIMessageRecipient = "sam@example.com"

    draft.suggest(from: contact, unlessSetIn: Person.PaymentMethods())

    XCTAssertNil(draft.venmoRecipient)
    XCTAssertNil(draft.iMessageRecipient)
  }

  func testSuggestSkipsSavedMethods() {
    let saved = Person.PaymentMethods(
      venmo: .init(username: "sam"),
      iMessage: .init(recipient: .init(kind: .custom, value: "sam@example.com")))
    var draft = PaymentMethodsDraft(saved)
    draft.venmoUsername = ""
    draft.customIMessageRecipient = ""

    draft.suggest(from: contact, unlessSetIn: saved)

    XCTAssertNil(draft.venmoRecipient)
    XCTAssertNil(draft.iMessageRecipient)
  }

  private var contact: ContactSummary {
    ContactSummary(
      identifier: "sam",
      displayName: "Sam",
      phoneNumbers: [.init(label: nil, value: "5551234567")])
  }
}
