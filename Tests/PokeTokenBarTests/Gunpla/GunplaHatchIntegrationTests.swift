import XCTest
@testable import PokeTokenBar

@MainActor
final class GunplaHatchIntegrationTests: XCTestCase {
    private let catalog = MachineCatalog.allBundled
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gunpla-\(UUID().uuidString).json")
    }

    private func store(rng: any RandomNumberGenerator = SeededRNG(seed: 7), fileURL: URL? = nil) -> CompanionStore {
        let fixedNow = now
        return CompanionStore(provider: catalog, clock: { fixedNow },
                              fileURL: fileURL ?? tempURL(), rng: rng,
                              defaults: UserDefaults(suiteName: "gunpla-\(UUID().uuidString)")!)
    }

    private func use(_ s: CompanionStore, _ today: Int) {
        s.update(todayTokensByProvider: ["test": today], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
    }

    /// Opens the box with the store's own update/hatch path (prefetch Tasks may run in between).
    private func openBox(_ s: CompanionStore) async {
        use(s, 0)
        use(s, s.eggHatchThreshold)
        let deadline = Date().addingTimeInterval(2)
        while s.state.active == nil, Date() < deadline {
            await s.hatchIfNeeded()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    /// Raises the active machine stage by stage until it graduates (or `stopAt` is reached).
    private func grow(_ s: CompanionStore, until stopAt: GunplaGrade? = nil) {
        for _ in 0..<10 {
            guard let a = s.state.active else { return }
            if let stopAt, GunplaID.decode(a.currentID)?.grade == stopAt { return }
            s.applyUsage(s.threshold)
        }
    }

    private func gradeEntry(_ machineID: Int, _ grades: [GunplaGrade], released: Bool = false) -> DexEntry {
        let ids = grades.map { GunplaID.encode(machineID: machineID, grade: $0) }
        return DexEntry(baseID: ids[0], finalID: ids[ids.count - 1], chainOrder: ids,
                        rarity: catalog.machine(id: machineID)!.rarity, caughtAt: now,
                        releasedAt: released ? now : nil)
    }

    func test_hatchFromBoxProducesCatalogMachineAtStartGrade() async throws {
        let s = store()
        await openBox(s)
        let active = try XCTUnwrap(s.state.active)
        let decoded = try XCTUnwrap(GunplaID.decode(active.baseID))
        let machine = try XCTUnwrap(catalog.machine(id: decoded.machineID))
        XCTAssertEqual(decoded.grade, machine.grades.first)
        XCTAssertEqual(active.stageIndex, 0)
        XCTAssertEqual(active.totalForms, machine.grades.count)
        XCTAssertEqual(active.rarity, machine.rarity)
        XCTAssertNil(s.state.pendingHatchID)
    }

    /// A store loaded from an old PokeTokenBar save whose pre-rolled species is a Pokémon id.
    private func legacyPendingStore() -> CompanionStore {
        let url = tempURL()
        try? Data(#"{"pendingHatchID":25}"#.utf8).write(to: url)
        let s = store(fileURL: url)
        XCTAssertEqual(s.state.pendingHatchID, 25)
        return s
    }

    func test_legacyNonGunplaPendingHatchIDIsDiscardedAndFreshChoiceMade() async throws {
        let s = legacyPendingStore()
        use(s, 0)
        use(s, s.eggHatchThreshold)
        await s.hatchIfNeeded()
        let active = try XCTUnwrap(s.state.active)
        XCTAssertNotNil(GunplaID.decode(active.baseID))
        XCTAssertNil(s.state.pendingHatchID)
    }

    func test_legacyPendingHatchIDIsReplacedByEggPrefetch() async throws {
        let s = legacyPendingStore()
        use(s, 0)
        use(s, 1)   // egg tick below the threshold triggers prefetch
        let deadline = Date().addingTimeInterval(2)
        while s.state.pendingHatchID == 25, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let pending = try XCTUnwrap(s.state.pendingHatchID)
        XCTAssertNotNil(GunplaID.decode(pending))
    }

    /// A pre-rolled id of a known machine whose grade is not (or no longer) released: the catalog refuses it.
    func test_pendingHatchIDWithUnreleasedGradeIsDiscardedAndBoxOpens() async throws {
        let unreleased = GunplaID.encode(machineID: 1, grade: .mgsd)   // RX-78-2 has no MGSD kit
        XCTAssertFalse(catalog.machine(id: 1)!.grades.contains(.mgsd))
        let url = tempURL()
        try Data(#"{"pendingHatchID":\#(unreleased)}"#.utf8).write(to: url)
        let s = store(fileURL: url)
        XCTAssertEqual(s.state.pendingHatchID, unreleased)
        use(s, 0)
        use(s, s.eggHatchThreshold)
        await s.hatchIfNeeded()
        let active = try XCTUnwrap(s.state.active)
        XCTAssertNotEqual(active.baseID, unreleased)
        let decoded = try XCTUnwrap(GunplaID.decode(active.baseID))
        XCTAssertTrue(try XCTUnwrap(catalog.machine(id: decoded.machineID)).grades.contains(decoded.grade))
    }

    /// Writes `active` into a save, loads it and runs update ticks until the store settles (or 2 s pass).
    private func storeSettlingActive(_ activeJSON: String, dexJSON: String = "[]") async throws -> CompanionStore {
        let url = tempURL()
        try Data(#"{"installBaselineSet":true,"active":\#(activeJSON),"dex":\#(dexJSON)}"#.utf8).write(to: url)
        let s = store(fileURL: url)
        XCTAssertNotNil(s.state.active)
        let deadline = Date().addingTimeInterval(2)
        while s.state.active != nil, Date() < deadline {
            use(s, 0)
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return s
    }

    func test_activePokemonIDBecomesBoxWithoutRetryingForever() async throws {
        let s = try await storeSettlingActive(
            #"{"baseID":25,"pathIDs":[25,26],"stageIndex":1,"usedAtStage":10,"rarity":"common","totalForms":2}"#)
        XCTAssertNil(s.state.active)
        XCTAssertTrue(s.isEgg)
        XCTAssertTrue(s.state.dex.isEmpty, "a Pokémon id is not a machine — nothing to record")
    }

    func test_activeGunplaIDWithRemovedGradeBecomesReleasedEntryAndBox() async throws {
        let removed = GunplaID.encode(machineID: 1, grade: .mgsd)
        let hg = GunplaID.encode(machineID: 1, grade: .hg)
        let rg = GunplaID.encode(machineID: 1, grade: .rg)
        let s = try await storeSettlingActive(
            #"{"baseID":\#(removed),"pathIDs":[\#(removed),\#(hg),\#(rg)],"stageIndex":1,"usedAtStage":10,"#
            + #""rarity":"rare","totalForms":4}"#)
        XCTAssertNil(s.state.active)
        XCTAssertTrue(s.isEgg)
        let entry = try XCTUnwrap(s.state.dex.last)
        XCTAssertEqual(entry.chainOrder, [hg], "only reached grades that are still released")
        XCTAssertNotNil(entry.releasedAt)
        XCTAssertEqual(s.state.collectionSnapshot(catalog: catalog).ownedGrades[1], [.hg])
    }

    func test_variantHatchIsShiny() async throws {
        let s = store(rng: SequenceRNG([0]))   // every variant roll hits
        await openBox(s)
        let active = try XCTUnwrap(s.state.active)
        XCTAssertTrue(active.isShiny)
        XCTAssertNotNil(catalog.machine(speciesID: active.baseID)?.variantOf)
        // Variant-ness rides through growth into the hangar record (was testGraduateCarriesIdentityToDex).
        grow(s)
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.dex.last?.isShiny, true)
    }

    func test_baseHatchIsNotShiny() async throws {
        let s = store(rng: SequenceRNG([1]))   // 1 % 32 != 0 → base machine
        await openBox(s)
        let active = try XCTUnwrap(s.state.active)
        XCTAssertFalse(active.isShiny)
        XCTAssertNil(catalog.machine(speciesID: active.baseID)?.variantOf)
    }

    /// [회귀, CompanionIdentityTests.testShinyBurstSurvivesOverflowEvolve 이관] 부화 이월로 즉시 한 단계 자라도
    /// 마지막 연출은 전용기 부화 버스트로 남는다 — evolve 가 덮지 않는다.
    func test_variantBurstSurvivesOverflowEvolve() async throws {
        let s = store(rng: SequenceRNG([0]))   // variant roll hits, weighted pick 0 → Char's Zaku II
        let variant = try XCTUnwrap(catalog.machine(id: 3))
        let firstStage = PokemonBalance.phaseThreshold(rarity: variant.rarity, totalForms: variant.grades.count, stageIndex: 0)
        use(s, 0)
        use(s, s.eggHatchThreshold + firstStage + 1_000)
        await s.hatchIfNeeded()
        let active = try XCTUnwrap(s.state.active)
        XCTAssertEqual(active.baseID, GunplaID.encode(machineID: 3, grade: .sd))
        XCTAssertTrue(active.isShiny)
        XCTAssertEqual(active.stageIndex, 1, "이월로 1회 성장했어야 함")
        XCTAssertEqual(s.celebration, .hatch(shiny: true))
    }

    func test_graduationRecordsAllGradeCellsInDex() async throws {
        let s = store()
        await s.hatch(baseID: GunplaID.encode(machineID: 2, grade: .sd))
        XCTAssertEqual(s.state.active?.totalForms, 5)
        grow(s)
        XCTAssertNil(s.state.active)
        let entry = try XCTUnwrap(s.state.dex.last)
        XCTAssertEqual(entry.chainOrder, [.sd, .hg, .rg, .mg, .pg].map { GunplaID.encode(machineID: 2, grade: $0) })
        XCTAssertNil(entry.releasedAt)
        XCTAssertEqual(s.state.collectionSnapshot(catalog: catalog).graduatedMachineIDs, [2])
    }

    func test_releasedMidwayResumesAtReachedGrade() async throws {
        // Everything but machine 1 is graduated, so the next box can only be machine 1.
        var seeded = CompanionState()
        seeded.installBaselineSet = true
        seeded.usedSinceInstall = 50_000_000_000
        seeded.dex = catalog.machines.filter { $0.id != 1 }.map { gradeEntry($0.id, $0.grades) }
        let url = tempURL()
        try JSONEncoder().encode(seeded).write(to: url)

        let s = store(fileURL: url)
        await s.hatch(baseID: GunplaID.encode(machineID: 1, grade: .sd))
        grow(s, until: .hg)
        XCTAssertEqual(s.state.active?.currentID, GunplaID.encode(machineID: 1, grade: .hg))

        XCTAssertTrue(s.buyEgg(nil))
        XCTAssertEqual(s.state.collectionSnapshot(catalog: catalog).ownedGrades[1], [.sd, .hg])
        await openBox(s)
        let active = try XCTUnwrap(s.state.active)
        XCTAssertEqual(active.baseID, GunplaID.encode(machineID: 1, grade: .hg))
        XCTAssertEqual(active.stageIndex, 0)
        XCTAssertEqual(active.totalForms, 4)   // hg → rg → mg → pg
        XCTAssertFalse(active.hasGrowthBoost)
    }

    /// The repeat-growth boost belongs to the machine: one graduated from a resumed HG start still earns it
    /// when the duplicate phase opens it again at SD.
    func test_duplicateOfMachineGraduatedFromResumedGradeGetsGrowthBoost() async throws {
        var seeded = CompanionState()
        seeded.installBaselineSet = true
        seeded.dex = catalog.machines.filter { $0.id != 1 }.map { gradeEntry($0.id, $0.grades) }
        seeded.dex.append(gradeEntry(1, [.sd, .hg], released: true))
        seeded.dex.append(gradeEntry(1, [.hg, .rg, .mg, .pg]))
        let hg = GunplaID.encode(machineID: 1, grade: .hg), pg = GunplaID.encode(machineID: 1, grade: .pg)
        seeded.collectedFinals = ["\(hg):\(pg)"]
        let url = tempURL()
        try JSONEncoder().encode(seeded).write(to: url)

        // 1 % 32 != 0 → base machine; pick 0 → first base in catalog order, machine 1.
        let s = store(rng: SequenceRNG([1, 0]), fileURL: url)
        await openBox(s)
        let active = try XCTUnwrap(s.state.active)
        XCTAssertEqual(active.baseID, GunplaID.encode(machineID: 1, grade: .sd))
        XCTAssertTrue(active.hasGrowthBoost)
    }

    // MARK: Resume pricing — stages are priced on the machine's full released-grade path.

    /// Thresholds the store charges from the current stage to graduation, read stage by stage.
    private func remainingStageCosts(_ s: CompanionStore) -> [Int] {
        var costs: [Int] = []
        for _ in 0..<10 {
            guard s.state.active != nil else { break }
            costs.append(s.threshold)
            s.applyUsage(s.threshold)
        }
        return costs
    }

    private func fullPathStage(_ i: Int) -> Int {
        // Machine 1 (rare): sd · hg · rg · mg · pg.
        PokemonBalance.phaseThreshold(rarity: .rare, totalForms: 5, stageIndex: i)
    }

    func test_resumedAtFinalGradeCostsOnlyThatStage() async throws {
        let s = store()
        await s.hatch(baseID: GunplaID.encode(machineID: 1, grade: .pg))
        XCTAssertEqual(remainingStageCosts(s), [fullPathStage(4)])
        XCTAssertEqual(fullPathStage(4), 1_000_000_000)
    }

    func test_resumedAtHGCostsTheRemainingStagesOfTheFullPath() async throws {
        let s = store()
        await s.hatch(baseID: GunplaID.encode(machineID: 1, grade: .hg))
        XCTAssertEqual(remainingStageCosts(s), (1...4).map(fullPathStage))
        XCTAssertEqual(remainingStageCosts(s).reduce(0, +), 0)   // graduated
    }

    func test_freshRunPricingIsUnchanged() async throws {
        let s = store()
        await s.hatch(baseID: GunplaID.encode(machineID: 1, grade: .sd))
        let costs = remainingStageCosts(s)
        XCTAssertEqual(costs, (0...4).map(fullPathStage))
        XCTAssertEqual(costs.reduce(0, +), PokemonBalance.graduationTotal(.rare))
    }

    func test_resumedPricingComposesWithCandyBoostAndDifficulty() async throws {
        var seeded = CompanionState()
        seeded.installBaselineSet = true
        seeded.inventory[ItemKind.rareCandy.rawValue] = 50
        seeded.dex = [gradeEntry(1, [.sd, .hg, .rg, .mg, .pg])]   // graduated before → repeat-growth boost
        let url = tempURL()
        try JSONEncoder().encode(seeded).write(to: url)
        let s = store(fileURL: url)
        await s.hatch(baseID: GunplaID.encode(machineID: 1, grade: .pg))
        XCTAssertEqual(s.state.active?.hasGrowthBoost, true)
        // PG stage 1.0B, halved by the boost → 500M at 100M per candy.
        XCTAssertEqual(s.threshold, PokemonBalance.phaseThreshold(rarity: .rare, totalForms: 5, stageIndex: 4,
                                                                  growthMultiplier: 2))
        XCTAssertEqual(s.threshold, 500_000_000)
        XCTAssertEqual(s.maxRareCandyUseCount, 5)
        s.setGrowthDifficulty(0.5)
        XCTAssertEqual(s.threshold, 250_000_000)
        XCTAssertEqual(s.maxRareCandyUseCount, 3)
        s.applyUsage(s.threshold / 2)
        XCTAssertEqual(s.menuGrowthText, s.l.menuGrowthProgress(50, isEgg: false))
    }

    func test_loadsStateWithLegacyPokemonFields() throws {
        let base = GunplaID.encode(machineID: 2, grade: .sd)
        let json = """
        {"installBaselineSet":true,"usedSinceInstall":12345,
         "inventory":{"mint":2,"rareCandy":1,"shinyCharm":1},
         "pendingForm":"a",
         "active":{"baseID":\(base),"pathIDs":[\(base)],"stageIndex":0,"usedAtStage":10,
                   "rarity":"common","totalForms":5,"isShiny":false,"nature":"timid","form":"a",
                   "dittoDisguise":\(base),"dittoRevealed":false,"profile":{"legacy":true}},
         "dex":[{"id":"old","baseID":25,"finalID":26,"chainOrder":[25,26],"rarity":"uncommon",
                 "nature":"bold","form":"a","profile":{"legacy":true}}]}
        """
        let url = tempURL()
        try Data(json.utf8).write(to: url)

        let s = store(fileURL: url)
        let active = try XCTUnwrap(s.state.active)
        XCTAssertEqual(active.baseID, base)
        XCTAssertEqual(active.usedAtStage, 10)
        XCTAssertEqual(s.state.usedSinceInstall, 12345)
        XCTAssertEqual(s.state.inventory["mint"], 2)
        XCTAssertEqual(s.state.dex.count, 1)
        // Legacy Pokémon dex entries are not catalog machines: nothing graduated, nothing owned but the active.
        let snapshot = s.state.collectionSnapshot(catalog: catalog)
        XCTAssertTrue(snapshot.graduatedMachineIDs.isEmpty)
        XCTAssertEqual(snapshot.ownedGrades, [2: [.sd]])
    }
}
