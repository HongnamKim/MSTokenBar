import XCTest
@testable import PokeTokenBar

/// The hangar groups the dex's synthetic (machine × grade) species into one cell per machine.
@MainActor
final class HangarCellTests: XCTestCase {
    private let catalog = MachineCatalog.allBundled
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func id(_ machineID: Int, _ grade: GunplaGrade) -> Int {
        GunplaID.encode(machineID: machineID, grade: grade)
    }

    private func entry(_ machineID: Int, _ grades: [GunplaGrade]) -> DexEntry {
        let ids = grades.map { id(machineID, $0) }
        return DexEntry(baseID: ids[0], finalID: ids[ids.count - 1], chainOrder: ids,
                        rarity: catalog.machine(id: machineID)?.rarity ?? .common, caughtAt: now,
                        isShiny: catalog.machine(id: machineID)?.isVariant ?? false)
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
        // 18 (first, order 0) sorts before 6 (zeta, order 1) despite the larger id.
        let s = try store(dex: [entry(11, [.sd]), entry(6, [.hg]), entry(18, [.mg]), entry(1, [.sd])])
        XCTAssertEqual(s.hangarCells.map(\.machineID), [1, 18, 6, 11])
        XCTAssertEqual(s.hangarCells.first { $0.machineID == 18 }?.isVariant, true)
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

    // Representative selection / raising flag / release — behavior carried over from the removed Unown tests.

    func test_representativeIsTheExactGradeAndPersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hangar-rep-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        var state = CompanionState()
        state.dex = [entry(1, [.sd, .hg]), entry(2, [.mg])]
        try JSONEncoder().encode(state).write(to: url)
        let s = CompanionStore(provider: catalog, fileURL: url)

        XCTAssertTrue(s.setRepresentativeSpeciesID(id(1, .hg)))
        XCTAssertTrue(s.isRepresentative(try XCTUnwrap(s.hangarCell(machineID: 1))))
        XCTAssertFalse(s.isRepresentative(try XCTUnwrap(s.hangarCell(machineID: 2))))
        XCTAssertEqual(s.representativeDexSpecies?.id, id(1, .hg))
        XCTAssertFalse(s.setRepresentativeSpeciesID(id(2, .pg)), "an unowned grade cannot be chosen")
        XCTAssertEqual(s.representativeSpeciesID, id(1, .hg), "a refused request keeps the earlier choice")

        let restored = CompanionStore(provider: catalog, fileURL: url)
        XCTAssertEqual(restored.representativeSpeciesID, id(1, .hg))
        XCTAssertTrue(restored.setRepresentativeSpeciesID(nil))
        XCTAssertNil(restored.representativeDexSpecies)
    }

    func test_releasingTheActiveMachineKeepsRepresentativeAndRecordsReachedGrades() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hangar-rel-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        var state = CompanionState()
        state.dex = [entry(1, [.sd])]
        state.active = MonState(baseID: id(2, .hg), pathIDs: [id(2, .hg), id(2, .rg)], stageIndex: 0,
                                usedAtStage: 5, rarity: .common, totalForms: 2)
        state.representativeSpeciesID = id(2, .hg)
        state.usedSinceInstall = FreshEgg.price
        try JSONEncoder().encode(state).write(to: url)
        let s = CompanionStore(provider: catalog, fileURL: url)
        XCTAssertTrue(try XCTUnwrap(s.hangarCell(machineID: 2)).isRaising)

        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertEqual(s.representativeSpeciesID, id(2, .hg), "the released machine is still owned")
        XCTAssertTrue(s.hangarCells.allSatisfy { !$0.isRaising })
        let released = try XCTUnwrap(s.state.dex.last)
        XCTAssertTrue(released.isReleased)
        XCTAssertEqual(released.chainOrder, [id(2, .hg)], "only the reached grade is recorded")
        XCTAssertTrue(s.state.collectedFinals.isEmpty, "releasing is not graduating")
        XCTAssertEqual(s.hangarCell(machineID: 2)?.ownedGrades, [.hg])
    }

    func test_detailIndividualsAndRaisingFlagAreScopedToTheExactGrade() throws {
        let active = MonState(baseID: id(1, .hg), pathIDs: [id(1, .hg), id(1, .rg)], stageIndex: 0,
                              usedAtStage: 0, rarity: .common, totalForms: 2)
        let s = try store(dex: [entry(1, [.sd, .hg]), entry(1, [.hg]), entry(2, [.hg])], active: active)

        let hgIndividuals = s.pokemonIndividuals(speciesID: id(1, .hg))
        XCTAssertEqual(hgIndividuals.count, 3, "two graduated HG builds of machine 1 plus the one raised now")
        XCTAssertTrue(hgIndividuals.allSatisfy { $0.finalID == id(1, .hg) })
        XCTAssertEqual(hgIndividuals.filter { s.isActiveDexEntry($0) }.count, 1)
        XCTAssertEqual(s.pokemonIndividuals(speciesID: id(1, .sd)).count, 0, "SD is only a reached stage of those builds")
        XCTAssertEqual(s.pokemonIndividuals(speciesID: id(2, .hg)).count, 1)
        XCTAssertEqual(s.dexSpecies.filter(\.isRaising).map(\.id), [id(1, .hg)])
    }

    /// The raising cell's RAISING badge sat on top of the sprite's grade mark; only one of them may draw.
    @MainActor
    func test_raisingCellDropsTheSpriteGradeMark() {
        XCTAssertFalse(HangarMachineCell.showsSpriteGradeBadge(isRaising: true))
        XCTAssertTrue(HangarMachineCell.showsSpriteGradeBadge(isRaising: false))
    }
}
