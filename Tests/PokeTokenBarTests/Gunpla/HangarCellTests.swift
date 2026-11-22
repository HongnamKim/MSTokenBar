import XCTest
@testable import PokeTokenBar

/// The hangar groups the dex's synthetic (machine × grade) species into one cell per machine.
@MainActor
final class HangarCellTests: XCTestCase {
    private let catalog = MachineCatalog.shared
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func id(_ machineID: Int, _ grade: GunplaGrade) -> Int {
        GunplaID.encode(machineID: machineID, grade: grade)
    }

    private func entry(_ machineID: Int, _ grades: [GunplaGrade]) -> DexEntry {
        let ids = grades.map { id(machineID, $0) }
        return DexEntry(baseID: ids[0], finalID: ids[ids.count - 1], chainOrder: ids,
                        rarity: catalog.machine(machineID)?.rarity ?? .common, caughtAt: now,
                        isShiny: catalog.machine(machineID)?.isVariant ?? false)
    }

    private func store(dex: [DexEntry], active: MonState? = nil, language: AppLanguage = .en) throws -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hangar-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        var state = CompanionState()
        state.dex = dex
        state.active = active
        state.language = language
        try JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: catalog, fileURL: url)
    }

    func test_cellsGroupGradesByMachine() throws {
        let active = MonState(baseID: id(2, .rg), pathIDs: [id(2, .rg), id(2, .mg)], stageIndex: 0,
                              usedAtStage: 0, rarity: .common, totalForms: 2)
        let s = try store(dex: [entry(2, [.sd, .hg])], active: active)
        XCTAssertEqual(s.hangarCells.count, 1)
        let cell = try XCTUnwrap(s.hangarCells.first)
        XCTAssertEqual(cell.machineID, 2)
        XCTAssertEqual(cell.id, 2)
        XCTAssertEqual(cell.ownedGrades, [.sd, .hg, .rg], "reached stages only — MG is not reached yet")
        XCTAssertEqual(cell.releasedGrades, [.sd, .hg, .rg, .mg, .pg])
        XCTAssertFalse(cell.isVariant)
        XCTAssertTrue(cell.isRaising)
    }

    func test_cellsSortBySeriesOrderThenMachineID() throws {
        // 12 (first, order 0) sorts before 6 (zeta, order 1) despite the larger id.
        let s = try store(dex: [entry(11, [.sd]), entry(6, [.hg]), entry(12, [.mg]), entry(1, [.sd])])
        XCTAssertEqual(s.hangarCells.map(\.machineID), [1, 12, 6, 11])
        XCTAssertEqual(s.hangarCells.first { $0.machineID == 12 }?.isVariant, true)
        XCTAssertTrue(s.hangarCells.allSatisfy { !$0.isRaising })
    }

    func test_nonGunplaSpeciesHaveNoCell() throws {
        let pikachu = DexEntry(baseID: 25, finalID: 25, chainOrder: [25], rarity: .rare, caughtAt: now)
        let s = try store(dex: [pikachu, entry(4, [.hg])])
        XCTAssertEqual(s.hangarCells.map(\.machineID), [4])
    }

    func test_cellOpensItsHighestOwnedGrade() throws {
        let s = try store(dex: [entry(1, [.sd, .hg]), entry(1, [.mg])])
        let cell = try XCTUnwrap(s.hangarCells.first)
        XCTAssertEqual(s.hangarDetailCollectionID(cell), String(id(1, .mg)))
        XCTAssertNotNil(s.dexSpecies.first { $0.collectionID == s.hangarDetailCollectionID(cell) },
                        "the detail page CollectionView opens exists")
        XCTAssertEqual(s.hangarCell(machineID: 1)?.ownedGrades, [.sd, .hg, .mg])
        XCTAssertNil(s.hangarCell(machineID: 2))
    }

    func test_storeCompletionsAndBadgesComeFromHangarCells() throws {
        let s = try store(dex: [entry(6, [.hg, .rg, .mg, .pg]), entry(7, [.hg, .rg, .mg, .pg]), entry(3, [.sd])])
        let zeta = try XCTUnwrap(s.dexCompletions.first { $0.seriesID == "zeta" })
        XCTAssertTrue(zeta.isComplete)
        XCTAssertEqual(s.dexCompletions.first { $0.seriesID == "first" }?.variantOwnedCells, 1)
        XCTAssertEqual(s.earnedDexBadges, [.series("zeta")])
    }
}
