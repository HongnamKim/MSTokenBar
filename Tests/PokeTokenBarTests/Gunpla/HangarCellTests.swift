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
        let completedZeta = catalog.machines.filter { $0.series == "zeta" }.map { entry($0.id, $0.grades) }
        let s = try store(dex: completedZeta + [entry(3, [.sd])])
        let zeta = try XCTUnwrap(s.dexCompletions.first { $0.seriesID == "zeta" })
        XCTAssertTrue(zeta.isComplete)
        XCTAssertEqual(s.dexCompletions.first { $0.seriesID == "first" }?.variantOwnedCells, 1)
        XCTAssertEqual(s.earnedDexBadges, [.series("zeta")])
    }

    // Silhouettes — base machines not built yet, shown so the player can see what is left.

    /// Hangar order over the whole catalog: series order, then machine id.
    private func hangarOrder(_ machines: [MachineRecord]) -> [Int] {
        let order = Dictionary(catalog.series.map { ($0.id, $0.order) }, uniquingKeysWith: { a, _ in a })
        return machines.sorted { (order[$0.series] ?? .max, $0.id) < (order[$1.series] ?? .max, $1.id) }.map(\.id)
    }

    func test_unbuiltCellsAreBaseMachinesNotBuiltYet() throws {
        let s = try store(dex: [entry(1, [.sd]), entry(18, [.hg])])
        let unbuilt = s.unbuiltHangarCells
        XCTAssertEqual(unbuilt.map(\.machineID),
                       hangarOrder(catalog.machines.filter { !$0.isVariant && $0.id != 1 }),
                       "every base machine except the built one, in hangar order; 전용기 stay hidden")
        XCTAssertTrue(unbuilt.allSatisfy { !$0.isBuilt && $0.ownedGrades.isEmpty && !$0.isRaising })
        XCTAssertEqual(unbuilt.first { $0.machineID == 16 }?.releasedGrades, [.sd, .hg, .mg])
        XCTAssertTrue(s.hangarCells.allSatisfy(\.isBuilt))
        XCTAssertEqual(s.hangarCells.map(\.machineID), [1, 18], "the hangar's own cells are unchanged")
    }

    func test_gridInterleavesSilhouettesInNumberOrder() throws {
        let s = try store(dex: [entry(16, [.hg]), entry(18, [.hg]), entry(6, [.sd])])
        let expected = hangarOrder(catalog.machines.filter { !$0.isVariant || $0.id == 18 })
        XCTAssertEqual(s.filteredHangarCells(includeUnbuilt: true).map(\.machineID), expected)
        XCTAssertEqual(s.filteredHangarCells(sort: .numberDesc, includeUnbuilt: true).map(\.machineID),
                       expected.reversed())
        XCTAssertEqual(s.filteredHangarCells().map(\.machineID), [16, 18, 6], "silhouettes are opt-in")
        XCTAssertEqual(s.filteredHangarCells(series: "zeta", includeUnbuilt: true).map(\.machineID),
                       hangarOrder(catalog.machines.filter { $0.series == "zeta" && !$0.isVariant }))
    }

    /// A silhouette gives away only its model number: no name, rarity or 전용기 status.
    func test_silhouettesStayOutOfRevealingFiltersAndSorts() throws {
        let s = try store(dex: [entry(1, [.sd])])
        XCTAssertEqual(s.hangarCellName(try XCTUnwrap(s.unbuiltHangarCells.first { $0.machineID == 16 })), "???")
        XCTAssertEqual(s.hangarCellName(try XCTUnwrap(s.hangarCell(machineID: 1))), "Gundam")

        XCTAssertEqual(s.filteredHangarCells(query: "Dom", includeUnbuilt: true).map(\.machineID), [],
                       "an unbuilt machine's name must not find it")
        let byModel = s.filteredHangarCells(query: "ms-09", includeUnbuilt: true)
        XCTAssertTrue(byModel.contains { $0.machineID == 16 }, "the model number is the one clue a silhouette gives")
        XCTAssertTrue(byModel.allSatisfy { catalog.machine(id: $0.machineID)?.modelNumber.contains("MS-09") == true })
        XCTAssertEqual(s.filteredHangarCells(rarity: .common, includeUnbuilt: true).map(\.machineID), [],
                       "a rarity filter would reveal each silhouette's rarity")
        XCTAssertEqual(s.filteredHangarCells(rarity: .rare, includeUnbuilt: true).map(\.machineID), [1])
        XCTAssertEqual(s.filteredHangarCells(variantOnly: true, includeUnbuilt: true).map(\.machineID), [])
        for sort in [CompanionStore.DexSortOption.nameAsc, .nameDesc, .rarityDesc] {
            let ids = s.filteredHangarCells(sort: sort, includeUnbuilt: true).map(\.machineID)
            XCTAssertEqual(ids.first, 1, "\(sort): built machines come first")
            XCTAssertEqual(Array(ids.dropFirst()), s.unbuiltHangarCells.map(\.machineID),
                           "\(sort): silhouettes keep hangar order — their names and rarities are unknown")
        }
    }

    /// A series can be chosen once it has base machines, even before the first build there.
    func test_seriesCanBeChosenWhenItHasCellsToShow() throws {
        let s = try store(dex: [entry(1, [.sd])])
        let cca = try XCTUnwrap(s.dexCompletions.first { $0.seriesID == "cca" })
        XCTAssertEqual(cca.ownedCells + cca.variantOwnedCells, 0)
        XCTAssertTrue(cca.hasHangarCells, "its base machines show as silhouettes")
        let onlyVariants = SeriesCompletion(seriesID: "x", ownedCells: 0, totalCells: 0,
                                            variantOwnedCells: 0, variantTotalCells: 3,
                                            builtMachines: 0, totalMachines: 0)
        XCTAssertFalse(onlyVariants.hasHangarCells, "unbuilt 전용기 stay hidden, so nothing to show")
        let builtVariant = SeriesCompletion(seriesID: "x", ownedCells: 0, totalCells: 0,
                                            variantOwnedCells: 1, variantTotalCells: 3,
                                            builtMachines: 0, totalMachines: 0)
        XCTAssertTrue(builtVariant.hasHangarCells)
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

    /// Hovering a floating pet names the suit on the first line; the box names itself.
    func test_hoverTitleNamesTheSuitOrTheBox() throws {
        let en = try store(dex: [entry(16, [.sd, .hg])])
        XCTAssertEqual(en.hoverTitle(speciesID: id(16, .hg)), "MS-09 · HG Dom")
        XCTAssertEqual(en.hoverTitle(speciesID: nil), en.l.eggName(nil))
        let ko = try store(dex: [entry(16, [.sd, .hg])], language: .ko)
        XCTAssertEqual(ko.hoverTitle(speciesID: id(16, .hg)), "MS-09 · HG 돔")

        let l = L(.en)
        // With and without a limit: the limit line rebuilds the text, and the title must survive it.
        for limit in [nil, 42.0] as [Double?] {
            let plain = FloatingPetView.hoverTooltip(todayTokens: 1, limitUtilization: limit, mode: .used, l: l,
                                                     prayers: 3)
            let titled = FloatingPetView.hoverTooltip(todayTokens: 1, limitUtilization: limit, mode: .used, l: l,
                                                      prayers: 3, title: "MS-09 · HG Dom")
            XCTAssertEqual(titled, "MS-09 · HG Dom\n" + plain, "limit \(String(describing: limit))")
        }
    }
}
