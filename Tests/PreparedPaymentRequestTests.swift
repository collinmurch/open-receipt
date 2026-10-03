import XCTest

@testable import open_receipt

final class PreparedPaymentRequestTests: XCTestCase {
  func testVenmoRequestOpensChargeURL() throws {
    let request = try XCTUnwrap(prepare(destination: .venmo(.init(kind: .username, value: "sam"))))

    guard case .openURL(let url) = request.action else { return XCTFail("Expected a URL") }
    XCTAssertEqual(url.scheme, "venmo")
  }

  func testCashAppRequestOpensPaymentURL() throws {
    let request = try XCTUnwrap(prepare(destination: .cashApp(.init(cashtag: "sam"))))

    guard case .openURL = request.action else { return XCTFail("Expected a URL") }
    XCTAssertEqual(request.method, .cashApp)
  }

  func testIMessageRequestComposesToRecipient() throws {
    let request = try XCTUnwrap(
      prepare(destination: .iMessage(.init(kind: .phoneNumber, value: "6468639557"))))

    guard case .compose(let recipient, let body) = request.action else {
      return XCTFail("Expected a message")
    }
    XCTAssertEqual(recipient, "6468639557")
    XCTAssertTrue(body.contains("$12.50"))
  }

  func testRequiresCompleteSplit() {
    XCTAssertNil(prepare(isSplitComplete: false))
  }

  func testVenmoRequiresUSD() {
    XCTAssertNil(prepare(currency: "EUR"))
  }

  func testCashAppRequiresUSD() {
    XCTAssertNil(prepare(destination: .cashApp(.init(cashtag: "sam")), currency: "EUR"))
  }

  func testIMessageAllowsOtherCurrencies() throws {
    let request = try XCTUnwrap(
      prepare(
        destination: .iMessage(.init(kind: .phoneNumber, value: "6468639557")), currency: "EUR"))

    XCTAssertEqual(request.currency, "EUR")
  }

  func testRequiresDestination() {
    XCTAssertNil(prepare(destination: nil))
  }

  func testSkipsOwner() {
    XCTAssertNil(prepare(source: .currentUser(contactIdentifier: nil)))
  }

  func testVenmoTitleNamesAmountAndMethod() throws {
    let request = try XCTUnwrap(prepare())

    XCTAssertEqual(request.title, "Request $12.50 in Venmo")
  }

  func testCashAppTitleOpensCashApp() throws {
    let request = try XCTUnwrap(prepare(destination: .cashApp(.init(cashtag: "sam"))))

    XCTAssertEqual(request.title, "Open $12.50 in Cash App")
  }

  func testNoteNamesMerchant() {
    XCTAssertEqual(
      PreparedPaymentRequest.note(merchantName: " Cafe "), "Open Receipt split for: Cafe")
  }

  func testNoteWithoutMerchant() {
    XCTAssertEqual(PreparedPaymentRequest.note(merchantName: "  "), "Open Receipt split")
  }

  private func prepare(
    destination: PaymentDestination? = .venmo(.init(kind: .username, value: "sam")),
    source: ReceiptParticipant.Source = .manual,
    currency: String = "USD",
    isSplitComplete: Bool = true
  ) -> PreparedPaymentRequest? {
    let share = ReceiptParticipantShare(
      participant: ReceiptParticipant(
        id: UUID(), source: source, displayName: "Sam", avatarData: nil),
      items: [ReceiptItemShare(itemID: UUID(), description: "Pizza", fraction: 1, amount: 12.5)],
      adjustments: [])
    return PreparedPaymentRequest(
      share: share,
      destination: destination,
      currency: currency,
      note: "Open Receipt split for: Cafe",
      isSplitComplete: isSplitComplete)
  }
}
