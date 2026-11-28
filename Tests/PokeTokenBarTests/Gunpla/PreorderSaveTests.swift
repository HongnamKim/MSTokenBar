import XCTest
@testable import PokeTokenBar

final class PreorderSaveTests: XCTestCase {
    private func decode(_ json: String) throws -> CompanionState {
        try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
    }
    private func building() -> MonState {
        let id = GunplaID.encode(machineID: 2, grade: .sd)
        return MonState(baseID: id, pathIDs: [id], plannedPathIDs: [id], stageIndex: 0, usedAtStage: 0,
                        rarity: .common, totalForms: 1)
    }

    func test_roundTrip() throws {
        var state = CompanionState()
        state.preorder = Preorder(machineID: 5, boxesOpened: 2)
        state.eggSeries = "0080"
        let decoded = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.preorder, Preorder(machineID: 5, boxesOpened: 2))
        XCTAssertEqual(decoded.eggSeries, "0080")
    }

    func test_oldSaveHasNeither() throws {
        let s = try decode(#"{"usedSinceInstall":7}"#)
        XCTAssertNil(s.preorder)
        XCTAssertNil(s.eggSeries)
    }

    func test_brokenValuesDecodeToNoneAndKeepTheRest() throws {
        let s = try decode(#"{"usedSinceInstall":7,"preorder":{"machineID":"x"},"eggSeries":12}"#)
        XCTAssertNil(s.preorder)
        XCTAssertNil(s.eggSeries)
        XCTAssertEqual(s.usedSinceInstall, 7)
    }

    func test_sanitizeClampsTheCount() {
        for (raw, expected) in [(-5, 0), (0, 0), (3, 3), (4, 3), (Int.max, 3)] {
            var s = CompanionState()
            s.preorder = Preorder(machineID: 5, boxesOpened: raw)
            XCTAssertEqual(SaveTransfer.sanitized(s).preorder?.boxesOpened, expected, "\(raw)")
        }
    }

    func test_sanitizeDropsAPreorderTheCatalogDoesNotKnow() {
        var s = CompanionState()
        s.preorder = Preorder(machineID: 9_999, boxesOpened: 1)
        XCTAssertNil(SaveTransfer.sanitized(s).preorder)
    }

    func test_sanitizeKeepsASeriesBoxOnlyWhileHeldAndKnown() {
        var held = CompanionState()
        held.eggSeries = "0080"
        XCTAssertEqual(SaveTransfer.sanitized(held).eggSeries, "0080")

        var unknown = CompanionState()
        unknown.eggSeries = "nope"
        XCTAssertNil(SaveTransfer.sanitized(unknown).eggSeries)

        var whileBuilding = CompanionState()
        whileBuilding.eggSeries = "0080"
        whileBuilding.active = building()
        whileBuilding.preorder = Preorder(machineID: 5, boxesOpened: 2)
        XCTAssertNil(SaveTransfer.sanitized(whileBuilding).eggSeries)
        XCTAssertEqual(SaveTransfer.sanitized(whileBuilding).preorder, Preorder(machineID: 5, boxesOpened: 2))
    }

    func test_importKeepsPreorderAndSeriesBox() {
        var imported = CompanionState()
        imported.preorder = Preorder(machineID: 5, boxesOpened: 2)
        imported.eggSeries = "0080"
        imported.pendingHatchID = GunplaID.encode(machineID: 30, grade: .hg)
        let rebased = SaveTransfer.rebasedForThisDevice(SaveTransfer.sanitized(imported), current: CompanionState(),
                                                        todayTokensByProvider: ["a": 1], todayDate: "d",
                                                        hasUsageData: true)
        XCTAssertEqual(rebased.preorder, Preorder(machineID: 5, boxesOpened: 2))
        XCTAssertEqual(rebased.eggSeries, "0080")
        XCTAssertEqual(rebased.pendingHatchID, imported.pendingHatchID)
    }
}
