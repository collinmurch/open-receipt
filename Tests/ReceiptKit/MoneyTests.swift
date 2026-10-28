import Foundation
import XCTest

#if SWIFT_PACKAGE
  @testable import ReceiptKit
#else
  @testable import open_receipt
#endif

final class MoneyTests: XCTestCase {
  func testFloatLiteralIsTheWrittenDecimal() {
    let amount: Money = 0.1

    XCTAssertEqual(amount.decimal, Decimal(string: "0.1"))
  }

  func testAddsExactly() {
    let amount: Money = 0.1 + 0.2

    XCTAssertEqual(amount, 0.3)
  }

  func testReadsDoubleAtFifteenSignificantDigits() {
    XCTAssertEqual(Money(0.1 + 0.2 as Double), 0.3)
    XCTAssertEqual(Money(1.005 * 100 as Double), 100.5)
  }

  func testRejectsDoublesThatArentAmounts() {
    XCTAssertNil(Money(Double.nan))
    XCTAssertNil(Money(Double.infinity))
  }

  func testRejectsDoublesTooLargeToHold() {
    XCTAssertNil(Money(1e300 as Double))
    XCTAssertNil(Money("1e300"))
  }

  func testReadsVeryLargeAndSmallDoubles() {
    XCTAssertEqual(Money(1e20 as Double)?.description, "100000000000000000000")
    XCTAssertEqual(Money(1e-5 as Double)?.description, "0.00001")
  }

  func testReadsPlainAndExponentNotation() {
    XCTAssertEqual(Money("12.34"), 12.34)
    XCTAssertEqual(Money("-3.25e-05")?.description, "-0.0000325")
    XCTAssertEqual(Money(".5"), 0.5)
    XCTAssertEqual(Money("7."), 7)
  }

  func testRejectsTextThatIsntADecimal() {
    XCTAssertNil(Money(""))
    XCTAssertNil(Money("12abc"))
    XCTAssertNil(Money("nan"))
    XCTAssertNil(Money("inf"))
    XCTAssertNil(Money("0x10"))
    XCTAssertNil(Money("1,5"))
  }

  func testWritesPlainNotation() {
    XCTAssertEqual((12.5 as Money).description, "12.5")
    XCTAssertEqual((-0.00001 as Money).description, "-0.00001")
    XCTAssertEqual((0 as Money).description, "0")
  }

  func testEqualAmountsWrittenDifferentlyAreEqualAndHashAlike() {
    let short = Money("12.5")
    let long = Money("12.50")

    XCTAssertEqual(short, long)
    XCTAssertEqual(short?.hashValue, long?.hashValue)
  }

  func testRoundsHalvesAwayFromZero() {
    XCTAssertEqual((1.005 as Money).rounded(places: 2), 1.01)
    XCTAssertEqual((-1.005 as Money).rounded(places: 2), -1.01)
    XCTAssertEqual((2.5 as Money).rounded(places: 0), 3)
  }

  func testCountsUnits() {
    XCTAssertEqual((12.34 as Money).units(places: 2), 1234)
    XCTAssertEqual((-0.1 as Money).units(places: 2), -10)
    XCTAssertEqual((1.005 as Money).units(places: 2), 101)
    XCTAssertEqual((1234 as Money).units(places: 0), 1234)
  }

  func testUnitsTooManyToCountAreNil() {
    XCTAssertNil((1e30 as Money).units(places: 2))
  }

  func testMakesAmountFromUnits() {
    XCTAssertEqual(Money(units: 125, places: 2), 1.25)
    XCTAssertEqual(Money(units: -5, places: 3), -0.005)
    XCTAssertEqual(Money(units: 1234, places: 0), 1234)
  }

  func testScalesWithoutRounding() {
    XCTAssertEqual((10 as Money) * 0.15, 1.5)
    XCTAssertEqual((19.99 as Money) * 0.18, 3.5982)
    XCTAssertEqual((1 as Money) / 4, 0.25)
  }

  func testScalesToZeroByAFactorThatIsntFinite() {
    XCTAssertEqual((10 as Money) * .nan, 0)
  }

  func testFindsTheFractionOfAWhole() {
    XCTAssertEqual((1 as Money).fraction(of: 4), 0.25)
  }

  func testFormatsAsCurrency() {
    let amount: Money = 1234.5

    XCTAssertEqual(
      amount.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))), "$1,234.50")
  }

  func testDecodesNumbersDigitForDigit() throws {
    let amounts = try JSONDecoder().decode([Money].self, from: Data("[0.1, 12.34, -5]".utf8))

    XCTAssertEqual(amounts, [0.1, 12.34, -5])
  }

  func testEncodesAsTheNumberItIs() throws {
    let amounts: [Money] = [0.1, 12.34]

    let data = try JSONEncoder().encode(amounts)

    XCTAssertEqual(String(decoding: data, as: UTF8.self), "[0.1,12.34]")
  }

  func testNegativeZeroIsZero() {
    XCTAssertEqual(Money(-0.0 as Double), 0)
    XCTAssertEqual(Money("-0"), 0)
    XCTAssertEqual(Money("-0.00"), 0)
    XCTAssertEqual(Money("-0")?.description, "0")
  }
}
