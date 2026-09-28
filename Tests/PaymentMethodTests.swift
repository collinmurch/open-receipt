#if !SWIFT_PACKAGE
  import XCTest
  @testable import open_receipt

  final class PaymentMethodTests: XCTestCase {
    func testContactDefaultOverridesGlobalDefault() {
      let methods = Person.PaymentMethods(
        defaultMethod: .cashApp,
        venmo: .init(username: "sam"),
        cashApp: .init(cashtag: "sam"))

      XCTAssertEqual(methods.destination(globalDefault: .venmo), .cashApp(.init(cashtag: "sam")))
    }

    func testMissingContactDefaultUsesGlobalDefault() {
      let methods = Person.PaymentMethods(
        venmo: .init(username: "sam"),
        cashApp: .init(cashtag: "sam"))

      XCTAssertEqual(
        methods.destination(globalDefault: .cashApp),
        .cashApp(.init(cashtag: "sam")))
    }

    func testNoneDisablesPaymentDestination() {
      let methods = Person.PaymentMethods(
        defaultMethod: PaymentMethod.none,
        venmo: .init(username: "sam"),
        cashApp: .init(cashtag: "sam"))

      XCTAssertNil(methods.destination(globalDefault: .venmo))
    }

    func testSelectedMethodWithoutDestinationIsUnavailable() {
      let methods = Person.PaymentMethods(defaultMethod: .iMessage)

      XCTAssertNil(methods.destination(globalDefault: .venmo))
    }

    func testLegacyPaymentMethodsDecodeWithoutNewFields() throws {
      let data = try XCTUnwrap(
        #"{"venmo":{"recipient":{"kind":"username","value":"sam"}}}"#.data(using: .utf8))

      let methods = try JSONDecoder().decode(Person.PaymentMethods.self, from: data)

      XCTAssertNil(methods.defaultMethod)
      XCTAssertEqual(methods.venmo?.recipient.value, "sam")
      XCTAssertNil(methods.cashApp)
      XCTAssertNil(methods.iMessage)
    }
  }
#endif
