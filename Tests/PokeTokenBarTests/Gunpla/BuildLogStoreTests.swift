import XCTest
@testable import PokeTokenBar

@MainActor
final class BuildLogStoreTests: XCTestCase {
    private final class Clock { var now = Date(timeIntervalSince1970: 1_700_000_000) }
    private let clock = Clock()
    private let catalog = MachineCatalog.allBundled
    /// RX-78-2: six released grades, rare.
    private var path: [Int] { catalog.machine(id: 1)!.grades.map { GunplaID.encode(machineID: 1, grade: $0) } }
    private var sd: Int { path[0] }

    private func store(seed: CompanionState? = nil, growth: Double = 1) throws -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("build-log-\(UUID().uuidString).json")
        if let seed { try JSONEncoder().encode(seed).write(to: url) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "build-log-\(UUID().uuidString)"))
        defaults.set(growth, forKey: "growthDifficulty")
        let clock = clock
        return CompanionStore(provider: catalog, clock: { clock.now }, fileURL: url,
                              rng: SeededRNG(seed: 7), defaults: defaults)
    }

    /// A save that already has its install baseline: both tools known, nothing claimed today.
    private func seeded(_ edit: (inout CompanionState) -> Void = { _ in }) -> CompanionState {
        var state = CompanionState()
        state.installBaselineSet = true
        state.lastDate = "d1"
        state.claimedTodayTokensByProvider = ["a": 0, "b": 0]
        edit(&state)
        return state
    }

    private func raising(usedAtStage: Int = 0) -> MonState {
        MonState(baseID: sd, pathIDs: [sd], plannedPathIDs: path, stageIndex: 0, usedAtStage: usedAtStage,
                 rarity: .rare, totalForms: path.count)
    }

    private func use(_ s: CompanionStore, _ today: [String: Int], date: String = "d1") {
        s.update(todayTokensByProvider: today, todayDate: date, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
    }

    private func log(_ s: CompanionStore) throws -> BuildLog { try XCTUnwrap(s.state.active?.buildLog) }

    private func total(_ log: BuildLog, _ tool: String) -> Int {
        log.stages.reduce(0) { $0 + ($1.tokensByProvider[tool] ?? 0) }
    }

    // MARK: box opening

    func test_openingABoxStartsTheRecord() async throws {
        let s = try store(seed: seeded())
        await s.hatch(baseID: sd)
        XCTAssertEqual(try log(s), BuildLog(openedAt: clock.now, stages: [BuildStage(speciesID: sd, reachedAt: clock.now)]))
    }

    func test_boxOverflowIsUnattributed() async throws {
        let s = try store(seed: seeded { $0.eggUsage = PokemonBalance.eggHatchThreshold + 123 })
        await s.hatch(baseID: sd)
        XCTAssertEqual(try log(s).stages, [BuildStage(speciesID: sd, reachedAt: clock.now, unattributed: 123)])
    }

    // MARK: usage

    func test_sameDayUsageIsRecordedPerProvider() async throws {
        let s = try store(seed: seeded())
        await s.hatch(baseID: sd)
        use(s, ["a": 100, "b": 40])
        XCTAssertEqual(try log(s).stages[0].tokensByProvider, ["a": 100, "b": 40])
        XCTAssertEqual(s.state.active?.usedAtStage, 140)
    }

    func test_firstUpdateOfANewDayIsRecordedPerProvider() async throws {
        let s = try store(seed: seeded())
        await s.hatch(baseID: sd)
        use(s, ["a": 70, "b": 30], date: "d2")
        XCTAssertEqual(try log(s).stages[0].tokensByProvider, ["a": 70, "b": 30])
    }

    func test_newlySeenAndRegressedProvidersAddNothing() async throws {
        let s = try store(seed: seeded())
        await s.hatch(baseID: sd)
        use(s, ["a": 100, "b": 0])
        use(s, ["a": 60, "b": 0, "c": 500])    // a fell back, c is seen for the first time
        XCTAssertEqual(try log(s).stages[0].tokensByProvider, ["a": 100])
        use(s, ["a": 80, "b": 0, "c": 510])
        XCTAssertEqual(try log(s).stages[0].tokensByProvider, ["a": 120, "c": 10])
    }

    func test_sandpaperIsRecordedApart() async throws {
        let s = try store(seed: seeded { $0.inventory[ItemKind.rareCandy.rawValue] = 1 })
        await s.hatch(baseID: sd)
        XCTAssertEqual(s.useRareCandy(), .progressed)
        XCTAssertEqual(try log(s).stages, [BuildStage(speciesID: sd, reachedAt: clock.now, sandpaper: RareCandy.xp)])
    }

    // MARK: grade-up, completion, release

    func test_gradeUpSplitsTheRecordAndStampsTheNewGrade() async throws {
        let s = try store(seed: seeded())
        await s.hatch(baseID: sd)
        let opened = clock.now, t = s.threshold
        s.applyUsage(.providers(["a": t - 100]))
        clock.now += 3_600
        s.applyUsage(.providers(["b": 300]))                  // banked t + 200: 200 carries over
        let moved = (t - 100) * 200 / (t + 200)
        XCTAssertEqual(try log(s).stages, [
            BuildStage(speciesID: sd, reachedAt: opened, tokensByProvider: ["a": t - 100 - moved, "b": 300]),
            BuildStage(speciesID: path[1], reachedAt: clock.now, tokensByProvider: ["a": moved])])
        XCTAssertEqual(s.state.active?.usedAtStage, 200)
    }

    func test_oneIncrementAcrossSeveralGradesConservesTheTotal() async throws {
        let s = try store(seed: seeded())
        await s.hatch(baseID: sd)
        s.applyUsage(.providers(["a": 430_000_000]))          // past the first two thresholds (≈142.9M + 285.7M)
        let record = try log(s)
        XCTAssertEqual(record.stages.map(\.speciesID), Array(path[0...2]))
        XCTAssertEqual(total(record, "a"), 430_000_000)
    }

    func test_completionMovesTheRecordIntoTheHangar() async throws {
        let s = try store(seed: seeded())
        await s.hatch(baseID: sd)
        let opened = clock.now
        var fed = 0
        for _ in 0..<10 {
            guard s.state.active != nil else { break }
            fed += s.threshold
            s.applyUsage(.providers(["a": s.threshold]))
        }
        XCTAssertNil(s.state.active)
        let entry = try XCTUnwrap(s.state.dex.last)
        let record = try XCTUnwrap(entry.buildLog)
        XCTAssertEqual(record.openedAt, opened)
        XCTAssertEqual(record.stages.map(\.speciesID), entry.chainOrder)
        XCTAssertEqual(total(record, "a"), fed)
    }

    func test_releaseMovesTheReachedGradesIntoTheHangar() async throws {
        let s = try store(seed: seeded { $0.usedSinceInstall = 1_000_000_000_000 })
        await s.hatch(baseID: sd)
        s.applyUsage(.providers(["a": s.threshold + 5]))      // now at the second grade
        XCTAssertTrue(s.buyFreshEgg())
        let entry = try XCTUnwrap(s.state.dex.last)
        XCTAssertTrue(entry.isReleased)
        XCTAssertEqual(entry.buildLog?.stages.map(\.speciesID), entry.chainOrder)
        XCTAssertEqual(entry.chainOrder, Array(path[0...1]))
    }

    // MARK: existing data and difficulty

    func test_machineWithoutARecordStartsFromItsBankedGrowth() throws {
        let s = try store(seed: seeded { $0.active = self.raising(usedAtStage: 500) })
        s.applyUsage(.providers(["a": 10]))
        XCTAssertEqual(try log(s), BuildLog(openedAt: nil, stages: [
            BuildStage(speciesID: sd, reachedAt: nil, tokensByProvider: ["a": 10], unattributed: 500)]))
    }

    func test_difficultyChangeLeavesTheRecordAlone() async throws {
        let s = try store(seed: seeded())
        await s.hatch(baseID: sd)
        s.applyUsage(.providers(["a": 1_000]))
        s.setGrowthDifficulty(0.5)
        XCTAssertEqual(s.state.active?.usedAtStage, 500)
        XCTAssertEqual(try log(s).stages[0].tokensByProvider, ["a": 1_000])
        let t = s.threshold
        s.applyUsage(.providers(["a": t]))
        XCTAssertEqual(s.state.active?.stageIndex, 1)
        XCTAssertEqual(total(try log(s), "a"), 1_000 + t)
    }

    // MARK: Review Focus

    func test_usageBeforeTheLineLoadsIsRecordedAndSplitOnceItLoads() async throws {
        let s = try store(seed: seeded { $0.active = self.raising() })
        XCTAssertNil(s.currentLine)
        let n = s.threshold + 7
        s.applyUsage(.providers(["a": n]))
        XCTAssertEqual(s.state.active?.stageIndex, 0, "no grade-up without the line")
        XCTAssertEqual(try log(s).stages[0].tokensByProvider, ["a": n])
        use(s, ["a": 0, "b": 0])                               // kicks the line load
        let deadline = Date().addingTimeInterval(2)
        while s.state.active?.stageIndex == 0, Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        let record = try log(s)
        XCTAssertEqual(record.stages.map(\.speciesID), Array(path[0...1]))
        XCTAssertEqual(total(record, "a"), n)
    }

    func test_secondBuildOfTheSameMachineStartsItsOwnRecord() async throws {
        let s = try store(seed: seeded())
        await s.hatch(baseID: sd)
        for _ in 0..<10 { guard s.state.active != nil else { break }; s.applyUsage(.providers(["a": s.threshold])) }
        let first = try XCTUnwrap(s.state.dex.last?.buildLog)
        clock.now += 86_400
        await s.hatch(baseID: sd)
        XCTAssertEqual(try log(s), BuildLog.opened(speciesID: sd, at: clock.now))
        XCTAssertEqual(s.state.dex.last?.buildLog, first)
    }

    func test_oneSandpaperAcrossSeveralGradesConservesItsAmount() async throws {
        let s = try store(seed: seeded { $0.inventory[ItemKind.rareCandy.rawValue] = 1 }, growth: 0.1)
        await s.hatch(baseID: sd)
        XCTAssertEqual(s.useRareCandy(), .evolved)
        let record = try log(s)
        XCTAssertGreaterThanOrEqual(record.stages.count, 3)
        XCTAssertEqual(record.stages.reduce(0) { $0 + $1.sandpaper }, RareCandy.xp)
    }

    // MARK: save boundary

    private func absurd() -> BuildLog {
        BuildLog(openedAt: nil, stages: [BuildStage(
            speciesID: sd, reachedAt: nil, tokensByProvider: ["a": Int.max, "b": -5],
            sandpaper: Int.min, unattributed: Int.max)])
    }

    func test_sanitizeClampsRecordNumbersOnTheMachineAndInTheHangar() {
        var mon = raising(usedAtStage: 5)
        mon.buildLog = absurd()
        let state = seeded {
            $0.active = mon
            $0.dex = [DexEntry(baseID: self.sd, finalID: self.sd, chainOrder: [self.sd], rarity: .rare,
                               caughtAt: nil, buildLog: self.absurd())]
        }
        let top = SaveTransfer.maxTokenValue
        let expected = [BuildStage(speciesID: sd, reachedAt: nil, tokensByProvider: ["a": top, "b": 0],
                                   sandpaper: 0, unattributed: top)]
        let clean = SaveTransfer.sanitized(state)
        XCTAssertEqual(clean.active?.buildLog?.stages, expected)
        XCTAssertEqual(clean.dex.first?.buildLog?.stages, expected)
        XCTAssertEqual(clean.active?.usedAtStage, 5, "a sum that differs from the banked growth is not repaired")
    }

    func test_absurdRecordOnDiskLoadsAndKeepsCounting() throws {
        var mon = raising(usedAtStage: Int.max)
        mon.buildLog = absurd()
        let s = try store(seed: seeded { $0.active = mon })
        s.applyUsage(.providers(["a": 1]))
        XCTAssertEqual(try log(s).stages[0].tokensByProvider["a"], SaveTransfer.maxTokenValue + 1)
    }

    func test_recordSurvivesExportAndImport() throws {
        var mon = raising(usedAtStage: 100)
        mon.buildLog = BuildLog(openedAt: clock.now, stages: [
            BuildStage(speciesID: sd, reachedAt: clock.now, tokensByProvider: ["a": 100])])
        let state = seeded { $0.active = mon }
        let envelope = try SaveTransfer.decode(
            SaveTransfer.encode(state: state, appVersion: "x", deviceName: "d", now: clock.now))
        XCTAssertEqual(envelope.state.active?.buildLog, mon.buildLog)
        XCTAssertEqual(envelope.schema, 2)
    }

    func test_importedRecordContinuesFromTheImportPoint() throws {
        var mon = raising(usedAtStage: 100)
        mon.buildLog = BuildLog(openedAt: clock.now, stages: [
            BuildStage(speciesID: sd, reachedAt: clock.now, tokensByProvider: ["a": 100])])
        let envelope = try SaveTransfer.decode(SaveTransfer.encode(
            state: seeded { $0.active = mon }, appVersion: "x", deviceName: "d", now: clock.now))
        let s = try store()
        try s.applySave(envelope, todayTokensByProvider: ["a": 5_000], todayDate: "d1", hasUsageData: true)
        use(s, ["a": 5_250])
        XCTAssertEqual(try log(s).stages[0].tokensByProvider, ["a": 350], "the 5,000 used before the import is not credited")
    }

    /// A start grade the catalog no longer serves sends the machine back to the box; only the surviving grades' record goes with it.
    func test_retiringAnUnservableMachineKeepsOnlyTheSurvivingGradesRecord() async throws {
        let gone = GunplaID.encode(machineID: 1, grade: .mgsd)   // RX-78-2 has no MGSD kit
        let hg = path[1]
        var mon = MonState(baseID: gone, pathIDs: [gone, hg], plannedPathIDs: [gone, hg], stageIndex: 1,
                           usedAtStage: 7, rarity: .rare, totalForms: 2)
        mon.buildLog = BuildLog(openedAt: clock.now, stages: [
            BuildStage(speciesID: gone, reachedAt: clock.now, tokensByProvider: ["a": 5]),
            BuildStage(speciesID: hg, reachedAt: clock.now, tokensByProvider: ["a": 7])])
        let s = try store(seed: seeded { $0.active = mon })
        use(s, ["a": 0, "b": 0])                               // kicks the line load, which cannot be served
        let deadline = Date().addingTimeInterval(2)
        while s.state.active != nil, Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertNil(s.state.active)
        let entry = try XCTUnwrap(s.state.dex.last)
        XCTAssertEqual(entry.chainOrder, [hg])
        XCTAssertEqual(entry.buildLog?.stages, [BuildStage(speciesID: hg, reachedAt: clock.now, tokensByProvider: ["a": 7])])
    }
}
