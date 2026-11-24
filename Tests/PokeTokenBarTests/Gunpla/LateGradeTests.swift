import XCTest
@testable import PokeTokenBar

/// A grade that reaches the catalog after the player already raised the machine — a kit released later,
/// or a grade line added to the game. A save written under the `before` catalog is loaded with `after`.
@MainActor
final class LateGradeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let series = SeriesRecord(id: "first", names: ["ko": "가", "en": "A", "ja": "あ"], order: 0)

    private func machine(_ id: Int, _ grades: [GunplaGrade]) -> MachineRecord {
        MachineRecord(id: id, modelNumber: "X-\(id)", names: ["ko": "가\(id)", "en": "A\(id)", "ja": "あ\(id)"],
                      series: "first", faction: "efsf", rarity: .rare, grades: grades,
                      gradeSources: nil, variantOf: nil, sprites: nil)
    }

    /// A one-machine catalog, so the next box can only be machine 1.
    private func catalog(_ grades: [GunplaGrade]) throws -> MachineCatalog {
        try MachineCatalog(machines: [machine(1, grades)], series: [series])
    }

    private func ids(_ grades: [GunplaGrade]) -> [Int] { grades.map { GunplaID.encode(machineID: 1, grade: $0) } }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("late-grade-\(UUID().uuidString).json")
    }

    private func store(_ catalog: MachineCatalog, fileURL: URL,
                       rng: any RandomNumberGenerator = SeededRNG(seed: 7)) -> CompanionStore {
        let fixedNow = now
        return CompanionStore(provider: catalog, clock: { fixedNow }, fileURL: fileURL, rng: rng,
                              defaults: UserDefaults(suiteName: "late-grade-\(UUID().uuidString)")!)
    }

    private func tick(_ s: CompanionStore, _ today: Int = 0) {
        s.update(todayTokensByProvider: ["test": today], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
    }

    /// Loads the save at `url` under `catalog` and waits for the active machine's line.
    private func reload(_ catalog: MachineCatalog, _ url: URL,
                        rng: any RandomNumberGenerator = SeededRNG(seed: 7)) async -> CompanionStore {
        let s = store(catalog, fileURL: url, rng: rng)
        let deadline = Date().addingTimeInterval(2)
        while s.state.active != nil, s.currentLine == nil, Date() < deadline {
            tick(s)
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return s
    }

    private func openBox(_ s: CompanionStore) async {
        tick(s, 0)
        tick(s, s.eggHatchThreshold)
        let deadline = Date().addingTimeInterval(2)
        while s.state.active == nil, Date() < deadline {
            await s.hatchIfNeeded()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    /// Raises the active machine stage by stage until it graduates (or `stopAt` is reached).
    private func grow(_ s: CompanionStore, until stopAt: GunplaGrade? = nil) {
        for _ in 0..<12 {
            guard let a = s.state.active else { return }
            if let stopAt, GunplaID.decode(a.currentID)?.grade == stopAt { return }
            s.applyUsage(s.threshold)
        }
    }

    /// A save where machine 1 finished a run through `grades` under an earlier catalog.
    private func saveWithGraduated(_ grades: [GunplaGrade]) throws -> URL {
        var seeded = CompanionState()
        seeded.installBaselineSet = true
        let chain = ids(grades)
        seeded.dex = [DexEntry(baseID: chain[0], finalID: chain[chain.count - 1], chainOrder: chain,
                               rarity: .rare, caughtAt: now)]
        let url = tempURL()
        try JSONEncoder().encode(seeded).write(to: url)
        return url
    }

    private func ownedGrades(_ s: CompanionStore) -> Set<GunplaGrade> {
        s.hangarCell(machineID: 1)?.ownedGrades ?? []
    }

    private func isCandidate(_ s: CompanionStore) -> Bool {
        HatchPlanner.hasCandidates(catalog: s.catalog, snapshot: s.state.collectionSnapshot(catalog: s.catalog), tier: nil)
    }

    private func stageCost(_ stage: Int, of total: Int, boosted: Bool = false) -> Int {
        PokemonBalance.phaseThreshold(rarity: .rare, totalForms: total, stageIndex: stage,
                                      growthMultiplier: boosted ? PokemonBalance.repeatGrowthMultiplier : 1)
    }

    // MARK: a grade inserted in the middle (RG between HG and MG)

    /// Trigger branch: the machine being raised is already PAST the inserted grade. Its reached path
    /// [SD, HG, MG] is no longer a parent→child chain, and used to be cut back to HG.
    func test_machineRaisedPastTheInsertedGradeIsNotDemoted() async throws {
        let url = tempURL()
        let before = store(try catalog([.sd, .hg, .mg, .pg]), fileURL: url)
        await before.hatch(baseID: ids([.sd])[0])
        grow(before, until: .mg)
        XCTAssertEqual(before.state.active?.pathIDs, ids([.sd, .hg, .mg]))

        let s = await reload(try catalog([.sd, .hg, .rg, .mg, .pg]), url)
        XCTAssertEqual(s.state.active?.pathIDs, ids([.sd, .hg, .mg]), "the reached grades stay as they were")
        XCTAssertEqual(s.currentSpeciesID, ids([.mg])[0])
        XCTAssertEqual(s.state.active?.plannedPathIDs, ids([.sd, .hg, .mg, .pg]))
        XCTAssertEqual(ownedGrades(s), [.sd, .hg, .mg])
        // MG is the 4th of 5 released grades now; its stage is priced there, not at RG's position.
        XCTAssertEqual(s.threshold, stageCost(3, of: 5))

        grow(s)
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.dex.last?.chainOrder, ids([.sd, .hg, .mg, .pg]))
        XCTAssertTrue(isCandidate(s), "RG is still an empty cell, so the machine comes back")
    }

    /// The other side of the same insertion: a machine still below the new grade simply grows through it.
    func test_machineRaisedBelowTheInsertedGradeGrowsThroughIt() async throws {
        let url = tempURL()
        let before = store(try catalog([.sd, .hg, .mg]), fileURL: url)
        await before.hatch(baseID: ids([.sd])[0])
        grow(before, until: .hg)

        let s = await reload(try catalog([.sd, .hg, .rg, .mg]), url)
        XCTAssertEqual(s.state.active?.pathIDs, ids([.sd, .hg]))
        XCTAssertEqual(s.state.active?.plannedPathIDs, ids([.sd, .hg, .rg, .mg]))
        grow(s)
        XCTAssertEqual(s.state.dex.last?.chainOrder, ids([.sd, .hg, .rg, .mg]))
        XCTAssertFalse(isCandidate(s))
    }

    /// Trigger branch: the machine graduated BEFORE the grade existed. It used to stay graduated forever,
    /// leaving the new cell unfillable.
    func test_graduatedMachineComesBackToFillTheInsertedGrade() async throws {
        let url = try saveWithGraduated([.sd, .hg, .mg, .pg])
        XCTAssertFalse(isCandidate(store(try catalog([.sd, .hg, .mg, .pg]), fileURL: url)), "complete before the change")

        let s = store(try catalog([.sd, .hg, .rg, .mg, .pg]), fileURL: url)
        XCTAssertTrue(isCandidate(s))
        XCTAssertFalse(s.earnedDexBadges.contains(.series("first")), "the series is open again")

        await openBox(s)
        let active = try XCTUnwrap(s.state.active)
        XCTAssertEqual(active.baseID, ids([.hg])[0], "starts at the owned grade just below the empty cell")
        XCTAssertEqual(active.plannedPathIDs, ids([.hg, .rg]), "and stops once the empty cell is filled")
        XCTAssertEqual(active.totalForms, 2)
        XCTAssertTrue(active.hasGrowthBoost, "a machine that graduated before grows at the repeat rate")
        XCTAssertFalse(s.isFinalStage)
        // Priced on the full 5-grade path at HG's and RG's positions.
        XCTAssertEqual(s.threshold, stageCost(1, of: 5, boosted: true))

        s.applyUsage(s.threshold)
        XCTAssertEqual(s.currentSpeciesID, ids([.rg])[0])
        XCTAssertTrue(s.isFinalStage, "RG ends this run even though MG and PG follow it in the catalog")
        XCTAssertEqual(s.lineNodes.count, 2, "no MG/PG preview past the end of the run")
        XCTAssertEqual(s.threshold, stageCost(2, of: 5, boosted: true))

        s.applyUsage(s.threshold)
        XCTAssertNil(s.state.active)
        let entry = try XCTUnwrap(s.state.dex.last)
        XCTAssertEqual(entry.chainOrder, ids([.hg, .rg]))
        XCTAssertNil(entry.releasedAt)
        XCTAssertEqual(ownedGrades(s), [.sd, .hg, .rg, .mg, .pg])
        XCTAssertFalse(isCandidate(s))
        XCTAssertTrue(s.earnedDexBadges.contains(.series("first")))
    }

    /// A run that stops before the top grade must survive a restart as it is, without a reroll.
    func test_refillRunSurvivesRestartUnchanged() async throws {
        let url = try saveWithGraduated([.sd, .hg, .mg, .pg])
        let after = try catalog([.sd, .hg, .rg, .mg, .pg])
        let first = store(after, fileURL: url)
        await openBox(first)
        XCTAssertEqual(first.state.active?.plannedPathIDs, ids([.hg, .rg]))

        let rng = CountingRNG(seed: 3)
        let s = await reload(after, url, rng: rng)
        XCTAssertNotNil(s.currentLine)
        XCTAssertEqual(s.state.active?.plannedPathIDs, ids([.hg, .rg]))
        XCTAssertEqual(s.state.active?.totalForms, 2)
        XCTAssertEqual(rng.callCount, 0)

        grow(s, until: .rg)
        let atGoal = await reload(after, url, rng: rng)
        XCTAssertEqual(atGoal.state.active?.plannedPathIDs, ids([.hg, .rg]))
        XCTAssertTrue(atGoal.isFinalStage)
        XCTAssertEqual(rng.callCount, 0)
        grow(atGoal)
        XCTAssertEqual(atGoal.state.dex.last?.chainOrder, ids([.hg, .rg]))
    }

    // MARK: a grade added at either end

    func test_graduatedMachineComesBackForANewTopGrade() async throws {
        let s = store(try catalog([.sd, .hg, .mg, .pg]), fileURL: try saveWithGraduated([.sd, .hg, .mg]))
        await openBox(s)
        XCTAssertEqual(s.state.active?.plannedPathIDs, ids([.mg, .pg]))
        grow(s)
        XCTAssertEqual(ownedGrades(s), [.sd, .hg, .mg, .pg])
        XCTAssertFalse(isCandidate(s))
    }

    func test_graduatedMachineComesBackForANewLowestGrade() async throws {
        let s = store(try catalog([.sd, .hg, .mg]), fileURL: try saveWithGraduated([.hg, .mg]))
        await openBox(s)
        XCTAssertEqual(s.state.active?.plannedPathIDs, ids([.sd]), "nothing owned below it: the run is the new grade alone")
        XCTAssertTrue(s.isFinalStage)
        XCTAssertEqual(s.threshold, stageCost(0, of: 3, boosted: true))
        grow(s)
        XCTAssertEqual(s.state.dex.last?.chainOrder, ids([.sd]))
        XCTAssertFalse(isCandidate(s))
    }

    /// A new top grade reaching a machine that is still being raised extends its run instead of ending it early.
    func test_runInProgressExtendsToANewTopGrade() async throws {
        let url = tempURL()
        let before = store(try catalog([.sd, .hg, .mg]), fileURL: url)
        await before.hatch(baseID: ids([.sd])[0])
        grow(before, until: .hg)

        let s = await reload(try catalog([.sd, .hg, .mg, .pg]), url)
        XCTAssertEqual(s.state.active?.plannedPathIDs, ids([.sd, .hg, .mg, .pg]))
        grow(s)
        XCTAssertEqual(s.state.dex.last?.chainOrder, ids([.sd, .hg, .mg, .pg]))
    }

    // MARK: Ver.Ka and MGEX (growth order between MG and PG, save codes after PG)

    func test_freshRunGrowsThroughVerKaAndMGEXInGrowthOrder() async throws {
        let grades: [GunplaGrade] = [.sd, .hg, .rg, .mg, .verka, .mgex, .pg]
        let url = tempURL()
        let s = store(try catalog(grades), fileURL: url)
        await s.hatch(baseID: ids([.sd])[0])
        XCTAssertEqual(s.state.active?.plannedPathIDs, ids(grades))
        grow(s, until: .mgex)
        XCTAssertEqual(s.state.active?.pathIDs, ids([.sd, .hg, .rg, .mg, .verka, .mgex]))

        // The run is kept across a restart although its ids are no longer ascending.
        let reloaded = await reload(try catalog(grades), url)
        XCTAssertEqual(reloaded.state.active?.pathIDs, ids([.sd, .hg, .rg, .mg, .verka, .mgex]))
        XCTAssertEqual(reloaded.threshold, stageCost(5, of: 7))
        grow(reloaded)
        XCTAssertEqual(reloaded.state.dex.last?.chainOrder, ids(grades))
        XCTAssertFalse(isCandidate(reloaded))
    }

    /// Ver.Ka reaching RX-78-2 after release is itself a mid-path insertion.
    func test_graduatedMachineComesBackForVerKaAndMGEX() async throws {
        let s = store(try catalog([.sd, .hg, .rg, .mg, .verka, .mgex, .pg]),
                      fileURL: try saveWithGraduated([.sd, .hg, .rg, .mg, .pg]))
        await openBox(s)
        XCTAssertEqual(s.state.active?.plannedPathIDs, ids([.mg, .verka, .mgex]))
        grow(s)
        XCTAssertEqual(ownedGrades(s), [.sd, .hg, .rg, .mg, .verka, .mgex, .pg])
        XCTAssertFalse(isCandidate(s))
    }

    /// Everything that ranks grades must use growth order: PG outranks Ver.Ka although its id is lower.
    func test_highestOwnedGradeAndListOrderIgnoreSaveCodes() async throws {
        let s = store(try catalog([.hg, .mg, .verka, .pg]), fileURL: try saveWithGraduated([.hg, .mg, .verka, .pg]))
        let cell = try XCTUnwrap(s.hangarCell(machineID: 1))
        XCTAssertEqual(s.hangarRepresentativeSpeciesID(cell), ids([.pg])[0])
        XCTAssertEqual(s.dexSpecies.map(\.id), ids([.hg, .mg, .verka, .pg]))
    }

    func test_catchLogNumberOrderPutsVerKaBeforePG() throws {
        var seeded = CompanionState()
        seeded.installBaselineSet = true
        func entry(_ name: String, _ grades: [GunplaGrade]) -> DexEntry {
            let chain = ids(grades)
            return DexEntry(id: name, baseID: chain[0], finalID: chain[chain.count - 1], chainOrder: chain,
                            rarity: .rare, caughtAt: now)
        }
        seeded.dex = [entry("pg", [.hg, .mg, .verka, .pg]), entry("verka", [.mg, .verka]), entry("mg", [.hg, .mg])]
        let url = tempURL()
        try JSONEncoder().encode(seeded).write(to: url)
        let s = store(try catalog([.hg, .mg, .verka, .pg]), fileURL: url)
        XCTAssertEqual(s.filteredDexEntries(sort: .numberAsc).map(\.id), ["mg", "verka", "pg"])
        XCTAssertEqual(s.filteredDexEntries(sort: .numberDesc).map(\.id), ["pg", "verka", "mg"])
    }

    // MARK: saves the current catalog does not fit

    /// A duplicate-phase run owns every grade ahead of it. When its plan stops fitting the catalog
    /// (a grade ahead was dropped) it is still re-planned to the top grade, not ended where it stands.
    func test_duplicateRunWithAnOutdatedPlanStillRunsToTheTop() async throws {
        let url = try saveWithGraduated([.sd, .hg, .rg, .mg])
        let before = store(try catalog([.sd, .hg, .rg, .mg]), fileURL: url)
        await openBox(before)
        XCTAssertEqual(before.state.active?.plannedPathIDs, ids([.sd, .hg, .rg, .mg]))

        let s = await reload(try catalog([.sd, .hg, .mg]), url)
        XCTAssertEqual(s.state.active?.plannedPathIDs, ids([.sd, .hg, .mg]))
        grow(s)
        XCTAssertEqual(s.state.dex.last?.chainOrder, ids([.sd, .hg, .mg]))
    }

    /// Before the line loads, a stage the plan cannot name is priced by its position after the start grade:
    /// a plan shorter than the reached path (damaged save), or a planned grade the catalog dropped.
    func test_stageIsPricedByPositionWhenThePlanDoesNotNameIt() throws {
        let catalog = try catalog([.sd, .hg, .mg])
        func mon(plan: [GunplaGrade]) -> MonState {
            MonState(baseID: ids([.hg])[0], pathIDs: ids([.hg, .mg]), plannedPathIDs: ids(plan), stageIndex: 1,
                     usedAtStage: 0, rarity: .rare, totalForms: 2)
        }
        XCTAssertEqual(mon(plan: [.hg]).phaseThreshold(catalog: catalog), stageCost(2, of: 3))
        XCTAssertEqual(mon(plan: [.hg, .rg, .mg]).phaseThreshold(catalog: catalog), stageCost(2, of: 3))
        XCTAssertNotEqual(stageCost(2, of: 3), stageCost(1, of: 3))
    }

    // MARK: unchanged rules

    /// A save written by 0.3.0, ids as literals: RX-78-2 finished through PG, Zaku II let go at RG.
    /// Nothing about it may read differently now that two grades were added.
    func test_saveWrittenBeforeVerKaReadsTheSame() throws {
        let json = """
        {"installBaselineSet":true,
         "dex":[{"id":"a","baseID":100010,"finalID":100015,"chainOrder":[100010,100012,100013,100014,100015],
                 "rarity":"rare"},
                {"id":"b","baseID":100020,"finalID":100023,"chainOrder":[100020,100022,100023],
                 "rarity":"common","releasedAt":700000000}]}
        """
        let url = tempURL()
        try Data(json.utf8).write(to: url)
        let s = store(.allBundled, fileURL: url)
        XCTAssertEqual(s.hangarCell(machineID: 1)?.ownedGrades, [.sd, .hg, .rg, .mg, .pg])
        XCTAssertEqual(s.hangarCell(machineID: 2)?.ownedGrades, [.sd, .hg, .rg])
        let snapshot = s.state.collectionSnapshot(catalog: s.catalog)
        XCTAssertEqual(snapshot.graduatedMachineIDs, [1])
        XCTAssertTrue(snapshot.isComplete(try XCTUnwrap(s.catalog.machine(id: 1))), "RX-78-2 stays graduated")
        XCTAssertEqual(HatchPlanner.runGrades(try XCTUnwrap(s.catalog.machine(id: 2)), snapshot: snapshot),
                       [.rg, .mg, .pg], "Zaku II still resumes at RG")
    }

    /// Everything complete: the duplicate phase still opens a machine at its first grade for a full run.
    func test_duplicatePhaseStillRunsTheWholePath() async throws {
        let s = store(try catalog([.sd, .hg, .mg]), fileURL: try saveWithGraduated([.sd, .hg, .mg]))
        XCTAssertFalse(isCandidate(s))
        await openBox(s)
        XCTAssertEqual(s.state.active?.plannedPathIDs, ids([.sd, .hg, .mg]))
        grow(s)
        XCTAssertEqual(s.state.dex.last?.chainOrder, ids([.sd, .hg, .mg]))
    }

    /// A machine let go at its top grade owns every cell but never finished: it still comes back there.
    func test_machineReleasedAtTheTopGradeStillComesBackToFinish() async throws {
        var seeded = CompanionState()
        seeded.installBaselineSet = true
        let chain = ids([.sd, .hg, .mg])
        seeded.dex = [DexEntry(baseID: chain[0], finalID: chain[2], chainOrder: chain, rarity: .rare,
                               caughtAt: now, releasedAt: now)]
        let url = tempURL()
        try JSONEncoder().encode(seeded).write(to: url)

        let s = store(try catalog([.sd, .hg, .mg]), fileURL: url)
        XCTAssertTrue(isCandidate(s))
        await openBox(s)
        XCTAssertEqual(s.state.active?.plannedPathIDs, ids([.mg]))
        XCTAssertFalse(try XCTUnwrap(s.state.active).hasGrowthBoost)
        grow(s)
        XCTAssertFalse(isCandidate(s))
    }
}
