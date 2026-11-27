import XCTest
@testable import PokeTokenBar

/// Series completion counts (machine, released grade) cells; base machines and variants are tallied apart.
final class HangarProgressTests: XCTestCase {
    private let catalog = MachineCatalog.allBundled

    /// A hangar cell owning `grades` of machine `id` (every released grade when nil).
    private func cell(_ id: Int, _ grades: [GunplaGrade]? = nil) -> HangarCell {
        let machine = catalog.machine(id: id)!
        return HangarCell(machineID: id, ownedGrades: Set(grades ?? machine.grades),
                          releasedGrades: machine.grades, isVariant: machine.isVariant, isRaising: false)
    }

    private func completion(_ seriesID: String, _ owned: [HangarCell]) -> SeriesCompletion? {
        HangarProgress.completions(owned: owned, catalog: catalog).first { $0.seriesID == seriesID }
    }

    func test_seriesCompletionCountsReleasedCellsOnly() throws {
        // 13 base machines with 42 released grades (RX-78-2 has Ver.Ka); 3 variants (Char's Zaku II, Gelgoog, Z'Gok) with 12.
        let empty = try XCTUnwrap(completion("first", []))
        XCTAssertEqual(empty.totalCells, 42)
        XCTAssertEqual(empty.variantTotalCells, 12)
        XCTAssertEqual(empty.ownedCells, 0)
        XCTAssertEqual(empty.variantOwnedCells, 0)

        // GM (4) has no SD kit: an owned grade outside the released list adds nothing.
        let owned = [cell(1, [.sd]), cell(4, [.sd, .hg]), cell(3, [.hg])]
        let first = try XCTUnwrap(completion("first", owned))
        XCTAssertEqual(first.ownedCells, 2)
        XCTAssertEqual(first.variantOwnedCells, 1)
        XCTAssertFalse(first.isComplete)
        XCTAssertFalse(first.isVariantComplete)
        XCTAssertEqual(first.id, "first")
    }

    /// The series list counts machines, so several grades of one machine are one. Dom, Z'Gok and Acguy in
    /// every released grade fill 10 of the 42 cells but are 3 of the 13 machines the grid shows.
    func test_builtMachinesCountAMachineOnceHoweverManyGrades() throws {
        let empty = try XCTUnwrap(completion("first", []))
        XCTAssertEqual(empty.builtMachines, 0)
        XCTAssertEqual(empty.totalMachines, 13)

        let first = try XCTUnwrap(completion("first", [cell(16), cell(19), cell(21)]))
        XCTAssertEqual(first.ownedCells, 10)
        XCTAssertEqual(first.builtMachines, 3)
        XCTAssertEqual(first.totalMachines, 13)
    }

    /// 전용기 keep their own tally: building one adds no machine to the series count.
    func test_builtMachinesLeaveVariantsOut() throws {
        let first = try XCTUnwrap(completion("first", [cell(16), cell(3)]))   // Dom + Char's Zaku II
        XCTAssertEqual(first.builtMachines, 1)
        XCTAssertEqual(first.variantOwnedCells, 5)
    }

    /// Modes share a hangar entry but grow on their own, so each mode is a machine of its own.
    func test_builtMachinesCountEachModeOnItsOwn() throws {
        let uc = try XCTUnwrap(completion("uc", [cell(11, [.hg, .rg]), cell(100, [.hg])]))
        XCTAssertEqual(uc.builtMachines, 2)
        XCTAssertEqual(uc.totalMachines, 19)
    }

    func test_completionsFollowCatalogSeriesOrder() {
        XCTAssertEqual(HangarProgress.completions(owned: [], catalog: catalog).map(\.seriesID),
                       ["first", "08th-ms-team", "0080", "0083", "the-origin", "thunderbolt", "cucuruz-doans-island",
                        "zeta", "zz", "cca", "beltorchika-children", "uc", "narrative", "hathaway", "f91", "victory",
                        "g-gundam", "gundam-wing", "endless-waltz", "after-war-x", "turn-a-gundam", "gundam-seed", "gundam-seed-destiny",
                        "gundam-00", "gundam-00-movie"])
    }

    func test_unicornModesShareOneHangarEntryAndKeepIndependentGrades() throws {
        let owned = [cell(11, [.hg, .rg]), cell(100, [.hg]), cell(115, [.pg]),
                     cell(116, [.hg]), cell(117, [.hg]), cell(118, [.hg, .rg])]
        let entries = HangarEntry.grouped(owned, catalog: catalog)
        XCTAssertEqual(entries.map(\.id), [11, 116])
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.displayed(preferredID: 100).ownedGrades, [.hg])
        XCTAssertEqual(entry.displayed(preferredID: 11).ownedGrades, [.hg, .rg])
        XCTAssertEqual(entry.displayed(preferredID: 115).ownedGrades, [.pg])
        let fullArmor = try XCTUnwrap(entries.first { $0.id == 116 })
        XCTAssertEqual(fullArmor.displayed(preferredID: 117).ownedGrades, [.hg])
        XCTAssertEqual(fullArmor.displayed(preferredID: 118).ownedGrades, [.hg, .rg])
        XCTAssertEqual(completion("uc", owned)?.ownedCells, 8)
        XCTAssertEqual(HangarEntry.grouped([cell(11, []), cell(100, [.mg])], catalog: catalog)
            .first?.displayed(preferredID: nil).machineID, 100)
    }

    func test_seriesBadgeWhenAllBaseCellsOwned() throws {
        let base = catalog.machines.filter { $0.series == "first" && !$0.isVariant }.map { cell($0.id) }
        let first = try XCTUnwrap(completion("first", base))
        XCTAssertTrue(first.isComplete)
        XCTAssertFalse(first.isVariantComplete)
        let badges = HangarProgress.earnedBadges(HangarProgress.completions(owned: base, catalog: catalog))
        XCTAssertEqual(badges, [.series("first")])

        // One missing grade (RX-78-2 PG) withholds the badge.
        let almost = [cell(1, [.sd, .hg, .rg, .mg])] + base.filter { $0.machineID != 1 }
        XCTAssertTrue(HangarProgress.earnedBadges(HangarProgress.completions(owned: almost, catalog: catalog)).isEmpty)
    }

    func test_variantBadgeSeparate() throws {
        let variants = catalog.machines.filter { $0.series == "first" && $0.isVariant }.map { cell($0.id) }
        let first = try XCTUnwrap(completion("first", variants))
        XCTAssertTrue(first.isVariantComplete)
        XCTAssertFalse(first.isComplete)
        // The ZZ and CCA variants still need to be collected for the global badge.
        XCTAssertEqual(HangarProgress.earnedBadges(HangarProgress.completions(owned: variants, catalog: catalog)),
                       [.seriesVariant("first")])
    }

    func test_seriesWithoutVariantsHasNoVariantBadge() throws {
        let zetaCells = catalog.machines.filter { $0.series == "zeta" }.map { cell($0.id) }
        let zeta = try XCTUnwrap(completion("zeta", zetaCells))
        XCTAssertTrue(zeta.isComplete)
        XCTAssertEqual(zeta.variantTotalCells, 0)
        XCTAssertFalse(zeta.isVariantComplete, "nothing to collect is not a completed variant set")
        let badges = HangarProgress.earnedBadges(HangarProgress.completions(owned: zetaCells, catalog: catalog))
        XCTAssertEqual(badges, [.series("zeta")])
    }

    func test_everyMachineEarnsAllAndAllVariantInStableOrder() {
        let everything = catalog.machines.map { cell($0.id) }
        let badges = HangarProgress.earnedBadges(HangarProgress.completions(owned: everything, catalog: catalog))
        XCTAssertEqual(badges, [.series("first"), .seriesVariant("first"), .series("08th-ms-team"),
                                .series("0080"), .series("0083"), .series("the-origin"), .seriesVariant("the-origin"),
                                .series("thunderbolt"), .series("cucuruz-doans-island"), .series("zeta"), .series("zz"), .seriesVariant("zz"),
                                .series("cca"), .seriesVariant("cca"), .series("beltorchika-children"), .series("uc"), .seriesVariant("uc"),
                                .series("narrative"), .series("hathaway"), .series("f91"), .series("victory"),
                                .series("g-gundam"), .series("gundam-wing"), .series("endless-waltz"),
                                .series("after-war-x"), .series("turn-a-gundam"), .series("gundam-seed"), .series("gundam-seed-destiny"),
                                .series("gundam-00"), .series("gundam-00-movie"), .all, .allVariant])

        let baseOnly = catalog.machines.filter { !$0.isVariant }.map { cell($0.id) }
        let baseBadges = HangarProgress.earnedBadges(HangarProgress.completions(owned: baseOnly, catalog: catalog))
        XCTAssertTrue(baseBadges.contains(.all))
        XCTAssertFalse(baseBadges.contains(.allVariant))
    }

    func test_newlyEarnedSkipsAlreadyNotifiedKeys() {
        let earned: [DexBadge] = [.series("first"), .seriesVariant("first"), .all]
        XCTAssertEqual(HangarProgress.newlyEarnedBadges(earned: earned, alreadyNotified: []), earned)
        XCTAssertEqual(HangarProgress.newlyEarnedBadges(earned: earned, alreadyNotified: ["series.first", "all"]),
                       [.seriesVariant("first")])
        // Keys from the Pokémon build (region.kanto, national, …) are simply ignored.
        XCTAssertEqual(HangarProgress.newlyEarnedBadges(earned: earned, alreadyNotified: ["region.kanto", "national"]),
                       earned)
    }

    func test_badgeKeysStable() {
        XCTAssertEqual(DexBadge.series("first").notificationKey, "series.first")
        XCTAssertEqual(DexBadge.seriesVariant("first").notificationKey, "seriesVariant.first")
        XCTAssertEqual(DexBadge.all.notificationKey, "all")
        XCTAssertEqual(DexBadge.allVariant.notificationKey, "allVariant")
    }
}
