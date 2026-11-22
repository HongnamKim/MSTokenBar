import XCTest
@testable import PokeTokenBar

@MainActor
final class GunplaHatchIntegrationTests: XCTestCase {
    private let catalog = MachineCatalog.shared
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gunpla-\(UUID().uuidString).json")
    }

    private func store(rng: any RandomNumberGenerator = SeededRNG(seed: 7), fileURL: URL? = nil) -> CompanionStore {
        let fixedNow = now
        return CompanionStore(provider: catalog, detailProvider: nil, clock: { fixedNow },
                              fileURL: fileURL ?? tempURL(), rng: rng,
                              dittoDisguiseRollingEnabled: false,
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
            s.applyUsage(a.phaseThreshold)
        }
    }

    private func gradeEntry(_ machineID: Int, _ grades: [GunplaGrade], released: Bool = false) -> DexEntry {
        let ids = grades.map { GunplaID.encode(machineID: machineID, grade: $0) }
        return DexEntry(baseID: ids[0], finalID: ids[ids.count - 1], chainOrder: ids,
                        rarity: catalog.machine(machineID)!.rarity, caughtAt: now,
                        releasedAt: released ? now : nil)
    }

    func test_hatchFromBoxProducesCatalogMachineAtStartGrade() async throws {
        let s = store()
        await openBox(s)
        let active = try XCTUnwrap(s.state.active)
        let decoded = try XCTUnwrap(GunplaID.decode(active.baseID))
        let machine = try XCTUnwrap(catalog.machine(decoded.machineID))
        XCTAssertEqual(decoded.grade, machine.grades.first)
        XCTAssertEqual(active.stageIndex, 0)
        XCTAssertEqual(active.totalForms, machine.grades.count)
        XCTAssertEqual(active.rarity, machine.rarity)
        XCTAssertNil(active.nature)
        XCTAssertNil(active.form)
        XCTAssertNil(active.profile)
        XCTAssertNil(active.dittoDisguise)
        XCTAssertNil(s.state.pendingHatchID)
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
        let s = store(rng: SequenceRNG([0]))   // variant roll hits, weighted pick 0 → machine 3 (rare, sd·hg·rg·mg)
        let firstStage = PokemonBalance.phaseThreshold(rarity: .rare, totalForms: 4, stageIndex: 0)
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
        XCTAssertEqual(s.state.collectionSnapshot(catalog: catalog).highestReachedGrade[1], .hg)
        await openBox(s)
        let active = try XCTUnwrap(s.state.active)
        XCTAssertEqual(active.baseID, GunplaID.encode(machineID: 1, grade: .hg))
        XCTAssertEqual(active.stageIndex, 0)
        XCTAssertEqual(active.totalForms, 4)   // hg → rg → mg → pg
        XCTAssertFalse(active.hasGrowthBoost)
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
        // Legacy Pokémon dex entries are not catalog machines: nothing graduated, nothing reached but the active.
        let snapshot = s.state.collectionSnapshot(catalog: catalog)
        XCTAssertTrue(snapshot.graduatedMachineIDs.isEmpty)
        XCTAssertEqual(snapshot.highestReachedGrade, [2: .sd])
    }
}
