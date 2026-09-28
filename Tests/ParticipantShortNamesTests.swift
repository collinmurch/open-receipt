#if !SWIFT_PACKAGE
  import XCTest
  @testable import open_receipt

  final class ParticipantShortNamesTests: XCTestCase {
    func testUsesFirstNameWhenUnique() {
      let alex = participant("Alex Smith")
      let sam = participant("Sam Jones")

      let names = ParticipantShortNames.names(for: [alex, sam])

      XCTAssertEqual(names[alex.id], "Alex")
      XCTAssertEqual(names[sam.id], "Sam")
    }

    func testAddsLastInitialForSharedFirstName() {
      let smith = participant("Alex Smith")
      let jones = participant("Alex Jones")

      let names = ParticipantShortNames.names(for: [smith, jones])

      XCTAssertEqual(names[smith.id], "Alex S.")
      XCTAssertEqual(names[jones.id], "Alex J.")
    }

    func testAddsLettersUntilLastNamesDiffer() {
      let smith = participant("Alex Smith")
      let smythe = participant("Alex Smythe")

      let names = ParticipantShortNames.names(for: [smith, smythe])

      XCTAssertEqual(names[smith.id], "Alex Smi.")
      XCTAssertEqual(names[smythe.id], "Alex Smy.")
    }

    func testDisambiguatesEachMemberAgainstWholeGroup() {
      let smith = participant("Alex Smith")
      let smythe = participant("Alex Smythe")
      let jones = participant("Alex Jones")

      let names = ParticipantShortNames.names(for: [smith, smythe, jones])

      XCTAssertEqual(names[smith.id], "Alex Smi.")
      XCTAssertEqual(names[smythe.id], "Alex Smy.")
      XCTAssertEqual(names[jones.id], "Alex J.")
    }

    func testMatchesFirstNamesCaseInsensitively() {
      let upper = participant("Alex Smith")
      let lower = participant("alex Jones")

      let names = ParticipantShortNames.names(for: [upper, lower])

      XCTAssertEqual(names[upper.id], "Alex S.")
      XCTAssertEqual(names[lower.id], "alex J.")
    }

    func testFallsBackToFullLastNameWhenOneIsPrefixOfAnother() {
      let smith = participant("Alex Smith")
      let smithers = participant("Alex Smithers")

      let names = ParticipantShortNames.names(for: [smith, smithers])

      XCTAssertEqual(names[smith.id], "Alex Smith")
      XCTAssertEqual(names[smithers.id], "Alex Smithe.")
    }

    func testFallsBackToFullNameForIdenticalNames() {
      let first = participant("Alex Smith")
      let second = participant("Alex Smith")

      let names = ParticipantShortNames.names(for: [first, second])

      XCTAssertEqual(names[first.id], "Alex Smith")
      XCTAssertEqual(names[second.id], "Alex Smith")
    }

    func testKeepsSingleWordNames() {
      let me = participant("Me")

      XCTAssertEqual(ParticipantShortNames.names(for: [me])[me.id], "Me")
    }

    func testUsesMultiWordLastName() {
      let vanDyke = participant("Alex Van Dyke")
      let vance = participant("Alex Vance")

      let names = ParticipantShortNames.names(for: [vanDyke, vance])

      XCTAssertEqual(names[vanDyke.id], "Alex Van D.")
      XCTAssertEqual(names[vance.id], "Alex Vanc.")
    }

    private func participant(_ name: String) -> ReceiptParticipant {
      ReceiptParticipant(id: UUID(), source: .manual, displayName: name, avatarData: nil)
    }
  }
#endif
