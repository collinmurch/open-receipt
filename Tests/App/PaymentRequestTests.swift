import XCTest

@testable import open_receipt

final class PaymentRequestTests: XCTestCase {
  func testVenmoRequestOpensChargeURL() throws {
    let request = try XCTUnwrap(self.request())

    guard case .openURL(let url) = request.action else { return XCTFail("Expected a URL") }
    XCTAssertEqual(url.scheme, "venmo")
  }

  func testCashAppRequestOpensPaymentURL() throws {
    let request = try XCTUnwrap(self.request(destination: .cashApp(.init(cashtag: "sam"))))

    guard case .openURL = request.action else { return XCTFail("Expected a URL") }
    XCTAssertEqual(request.method, .cashApp)
  }

  func testIMessageRequestComposesToRecipient() throws {
    let request = try XCTUnwrap(
      self.request(destination: .iMessage(.init(kind: .phoneNumber, value: "6468639557"))))

    guard case .compose(let recipient, let body) = request.action else {
      return XCTFail("Expected a message")
    }
    XCTAssertEqual(recipient, "6468639557")
    XCTAssertTrue(body.contains("$12.50"))
  }

  func testVenmoRequiresUSD() {
    XCTAssertEqual(reason(currency: "EUR"), "Venmo requests require a USD receipt.")
  }

  func testCashAppRequiresUSD() {
    XCTAssertNil(request(destination: .cashApp(.init(cashtag: "sam")), currency: "EUR"))
  }

  func testIMessageAllowsOtherCurrencies() throws {
    let request = try XCTUnwrap(
      self.request(
        destination: .iMessage(.init(kind: .phoneNumber, value: "6468639557")), currency: "EUR"))

    XCTAssertEqual(request.currency, "EUR")
  }

  func testMissingDestinationNeedsPaymentMethod() {
    guard case .needsPaymentMethod = state(destination: nil) else {
      return XCTFail("Expected a payment method to be needed")
    }
  }

  func testInvalidRecipientIsUnavailableWithoutReason() {
    guard case .unavailable(nil) = state(destination: .venmo(.init(kind: .phoneNumber, value: "1")))
    else { return XCTFail("Expected no request") }
  }

  func testZeroShareHasNothingToRequest() {
    XCTAssertEqual(reason(amount: 0), "Nothing to request from Sam.")
  }

  func testZeroShareWithoutDestinationHasNothingToRequest() {
    XCTAssertEqual(reason(destination: nil, amount: 0), "Nothing to request from Sam.")
  }

  func testNegativeShareSaysOwnerOwesThem() {
    XCTAssertEqual(reason(amount: -2.5), "You owe Sam $2.50.")
  }

  func testVenmoTitleNamesAmount() throws {
    XCTAssertEqual(try XCTUnwrap(request()).title, "Request $12.50")
  }

  func testCashAppTitleOpensCashApp() throws {
    let request = try XCTUnwrap(self.request(destination: .cashApp(.init(cashtag: "sam"))))

    XCTAssertEqual(request.title, "Open $12.50")
  }

  func testNoteNamesMerchant() {
    XCTAssertEqual(PaymentRequest.note(merchantName: " Cafe "), "Open Receipt split for: Cafe")
  }

  func testNoteWithoutMerchant() {
    XCTAssertEqual(PaymentRequest.note(merchantName: "  "), "Open Receipt split")
  }

  func testVenmoBuildsChargeRequest() throws {
    let url = try XCTUnwrap(
      PaymentRequest.venmoURL(
        recipient: recipient(.username, "sam"), amount: 12.34, note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(components.scheme, "venmo")
    XCTAssertEqual(components.host, "paycharge")
    XCTAssertEqual(queryValue("txn", in: components), "charge")
  }

  func testVenmoIncludesRecipient() throws {
    let url = try XCTUnwrap(
      PaymentRequest.venmoURL(
        recipient: recipient(.username, "sam"), amount: 12.34, note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("recipients", in: components), "sam")
  }

  func testVenmoNormalizesRecipient() throws {
    let url = try XCTUnwrap(
      PaymentRequest.venmoURL(
        recipient: recipient(.username, "  @sam  "), amount: 12.34, note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("recipients", in: components), "sam")
  }

  func testVenmoIncludesPhoneNumberRecipient() throws {
    let url = try XCTUnwrap(
      PaymentRequest.venmoURL(
        recipient: recipient(.phoneNumber, "+1 646-863-9557"),
        amount: 12.34,
        note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("recipients", in: components), "6468639557")
  }

  func testVenmoNormalizesTenDigitPhoneNumberRecipient() throws {
    let url = try XCTUnwrap(
      PaymentRequest.venmoURL(
        recipient: recipient(.phoneNumber, "(646) 863-9557"),
        amount: 12.34,
        note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("recipients", in: components), "6468639557")
  }

  func testVenmoRejectsPhoneNumberWithoutTenUSDigits() {
    XCTAssertNil(
      PaymentRequest.venmoURL(
        recipient: recipient(.phoneNumber, "+44 20 7946 0958"),
        amount: 12.34,
        note: "Receipt split"))
  }

  func testVenmoIncludesEmailAddressRecipient() throws {
    let url = try XCTUnwrap(
      PaymentRequest.venmoURL(
        recipient: recipient(.emailAddress, "sam@example.com"),
        amount: 12.34,
        note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("recipients", in: components), "sam@example.com")
  }

  func testVenmoFormatsAmountWithTwoDecimalPlaces() throws {
    let url = try XCTUnwrap(
      PaymentRequest.venmoURL(
        recipient: recipient(.username, "sam"), amount: 12.3, note: "Receipt split"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("amount", in: components), "12.30")
  }

  func testVenmoEncodesNote() throws {
    let url = try XCTUnwrap(
      PaymentRequest.venmoURL(
        recipient: recipient(.username, "sam"), amount: 12.34, note: "Cafe & Bakery"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(queryValue("note", in: components), "Cafe & Bakery")
  }

  func testVenmoPercentEncodesPlusInNote() throws {
    let url = try XCTUnwrap(
      PaymentRequest.venmoURL(
        recipient: recipient(.username, "sam"),
        amount: 12.34,
        note: "Open Receipt split for: A+B Pizza"))

    XCTAssertTrue(url.absoluteString.contains("A%2BB"))
  }

  func testVenmoPercentEncodesPlusInEmailRecipient() throws {
    let url = try XCTUnwrap(
      PaymentRequest.venmoURL(
        recipient: recipient(.emailAddress, "sam+food@example.com"),
        amount: 12.34,
        note: "Receipt split"))

    XCTAssertTrue(url.absoluteString.contains("sam%2Bfood@example.com"))
  }

  func testVenmoRejectsEmptyRecipient() {
    XCTAssertNil(
      PaymentRequest.venmoURL(
        recipient: recipient(.username, " @ "), amount: 12.34, note: "Receipt split"))
  }

  func testCashAppBuildsPaymentLink() throws {
    let url = try XCTUnwrap(PaymentRequest.cashAppURL(cashtag: "SomeCashtag", amount: 12.5))

    XCTAssertEqual(url.absoluteString, "https://cash.app/$SomeCashtag/12.50")
  }

  func testCashAppNormalizesLeadingDollarSign() throws {
    let url = try XCTUnwrap(PaymentRequest.cashAppURL(cashtag: " $$sam-123 ", amount: 2))

    XCTAssertEqual(url.absoluteString, "https://cash.app/$sam-123/2.00")
  }

  func testCashAppRejectsEmptyCashtag() {
    XCTAssertNil(PaymentRequest.cashAppURL(cashtag: " $ ", amount: 12.5))
  }

  func testCashAppRejectsUnsafeCashtagPath() {
    XCTAssertNil(PaymentRequest.cashAppURL(cashtag: "sam/other", amount: 12.5))
  }

  func testMessageAsksForAmountWithNote() throws {
    let body = try XCTUnwrap(
      PaymentRequest.messageBody(
        amount: 12.5, currency: "USD", note: "Open Receipt split for: Cafe"))

    XCTAssertEqual(
      body, "Could you pay me $12.50 when you get a chance? Open Receipt split for: Cafe")
  }

  func testMessageWithoutNote() throws {
    let body = try XCTUnwrap(
      PaymentRequest.messageBody(amount: 12.5, currency: "USD", note: "  "))

    XCTAssertEqual(body, "Could you pay me $12.50 when you get a chance?")
  }

  func testMessageFormatsAmountForLocale() throws {
    let body = try XCTUnwrap(
      PaymentRequest.messageBody(
        amount: 1234.5, currency: "EUR", note: "", locale: Locale(identifier: "de_DE")))

    XCTAssertEqual(body, "Could you pay me 1.234,50\u{00A0}€ when you get a chance?")
  }

  func testMessageRejectsInvalidCurrency() {
    XCTAssertNil(PaymentRequest.messageBody(amount: 12.5, currency: "US", note: "Receipt split"))
  }

  private func state(
    destination: PaymentDestination? = .venmo(.init(kind: .username, value: "sam")),
    currency: String = "USD",
    amount: Money = 12.5
  ) -> PaymentRequestState {
    PaymentRequestState(
      share: ReceiptParticipantShare(
        participant: ReceiptParticipant(id: UUID(), source: .manual, displayName: "Sam"),
        items: [],
        adjustments: [],
        units: 0,
        total: amount),
      destination: destination,
      currency: currency,
      note: "Open Receipt split for: Cafe")
  }

  private func request(
    destination: PaymentDestination? = .venmo(.init(kind: .username, value: "sam")),
    currency: String = "USD"
  ) -> PaymentRequest? {
    guard case .ready(let request) = state(destination: destination, currency: currency) else {
      return nil
    }
    return request
  }

  private func reason(
    destination: PaymentDestination? = .venmo(.init(kind: .username, value: "sam")),
    currency: String = "USD",
    amount: Money = 12.5
  ) -> String? {
    guard
      case .unavailable(let reason) = state(
        destination: destination, currency: currency, amount: amount)
    else { return nil }
    return reason
  }

  private func recipient(
    _ kind: Person.Venmo.Recipient.Kind,
    _ value: String
  ) -> Person.Venmo.Recipient {
    .init(kind: kind, value: value)
  }

  private func queryValue(_ name: String, in components: URLComponents) -> String? {
    components.queryItems?.first { $0.name == name }?.value
  }
}
