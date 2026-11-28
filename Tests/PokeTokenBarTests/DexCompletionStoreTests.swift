import XCTest
@testable import PokeTokenBar

private enum DexStoreTestError: Error { case offline }

/// Returns lines from memory and fails prefetch so no network is touched.
private struct OfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [baseSpeciesID: ["en": "Mon"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw DexStoreTestError.offline }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw DexStoreTestError.offline }
}

@MainActor
final class DexCompletionStoreTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-dex-\(UUID().uuidString).json")
    }

    private let catalog = MachineCatalog.allBundled

    /// One DexEntry per machine, owning the given grades (every released grade when nil).
    private func entries(_ owned: [Int: [GunplaGrade]?]) -> [DexEntry] {
        owned.keys.sorted().map { machineID in
            let machine = catalog.machine(id: machineID)!
            let ids = (owned[machineID]! ?? machine.grades).map { GunplaID.encode(machineID: machineID, grade: $0) }
            return DexEntry(baseID: ids[0], finalID: ids[ids.count - 1], chainOrder: ids,
                            rarity: machine.rarity, caughtAt: Date(), isShiny: machine.isVariant)
        }
    }

    private func store(owning owned: [Int: [GunplaGrade]?], active: MonState? = nil) throws -> CompanionStore {
        var state = CompanionState()
        state.dex = entries(owned)
        state.active = active
        let url = tempURL()
        try JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: catalog, fileURL: url)
    }

    private var zeta: [Int: [GunplaGrade]?] {
        Dictionary(uniqueKeysWithValues: catalog.machines.filter { $0.series == "zeta" }.map {
            ($0.id, nil as [GunplaGrade]?)
        })
    }

    private var zetaWithoutPGZetaGundam: [Int: [GunplaGrade]?] {
        var owned = zeta
        owned[7] = [.sd, .hg, .rg, .mg, .verka]
        return owned
    }

    func testEmptyStoreHasNoCompletionsAndIsSeeded() throws {
        let url = tempURL()
        try JSONEncoder().encode(CompanionState()).write(to: url)
        let s = CompanionStore(provider: OfflineProvider(), fileURL: url)
        XCTAssertTrue(s.dexCompletions.allSatisfy { !$0.isComplete })
        XCTAssertTrue(s.earnedDexBadges.isEmpty)
        XCTAssertTrue(s.state.dexCompletionsSeeded, "fresh load seeds the completion tracker")
        XCTAssertTrue(s.state.notifiedDexCompletions.isEmpty)
    }

    func testCompleteSeriesIsReportedComplete() throws {
        let s = try store(owning: zeta)
        let completion = s.dexCompletions.first { $0.seriesID == "zeta" }
        XCTAssertEqual(completion?.ownedCells, 35)   // 34 + Zeta Gundam's Ver.Ka
        XCTAssertTrue(completion?.isComplete ?? false)
        XCTAssertTrue(s.earnedDexBadges.contains(.series("zeta")))
    }

    /// A save that was already complete before the feature shipped must not fire a notification burst:
    /// seeding records the earned badges as already-notified on first load.
    func testExistingCompletionsAreSeededAsNotifiedWithoutFiring() throws {
        let s = try store(owning: zeta)
        XCTAssertTrue(s.state.dexCompletionsSeeded)
        XCTAssertTrue(s.state.notifiedDexCompletions.contains(DexBadge.series("zeta").notificationKey))
        // Nothing is "newly earned" after seeding, so a re-check adds no keys and fires nothing.
        let before = s.state.notifiedDexCompletions
        s.checkDexCompletions()
        XCTAssertEqual(s.state.notifiedDexCompletions, before)
    }

    func testSeriesFilterReturnsOnlyMachinesInThatSeries() throws {
        let s = try store(owning: [1: [.sd], 2: [.hg], 6: [.hg], 8: [.sd]])
        XCTAssertEqual(s.filteredHangarCells(series: "first").map(\.machineID), [1, 2])
        XCTAssertEqual(s.filteredHangarCells(series: "zeta").map(\.machineID), [6])
        XCTAssertTrue(s.filteredHangarCells(series: "uc").isEmpty)
        XCTAssertEqual(s.filteredHangarCells(series: nil).map(\.machineID), [1, 2, 6, 8])
    }

    func testOwningEveryMachineEarnsEveryBadge() throws {
        let everything = Dictionary(uniqueKeysWithValues: catalog.machines.map { ($0.id, nil as [GunplaGrade]?) })
        let s = try store(owning: everything)
        XCTAssertTrue(s.earnedDexBadges.contains(.all))
        XCTAssertTrue(s.earnedDexBadges.contains(.allVariant))
        XCTAssertTrue(catalog.series.allSatisfy { s.earnedDexBadges.contains(.series($0.id)) })
        XCTAssertEqual(s.state.notifiedDexCompletions, Set(s.earnedDexBadges.map(\.notificationKey)))
    }

    /// The raising machine's reached grade is owned before it graduates, so it can finish a series.
    func testActiveReachedGradeCompletesTheSeries() throws {
        let partial = try store(owning: zetaWithoutPGZetaGundam)
        XCTAssertFalse(partial.earnedDexBadges.contains(.series("zeta")))

        let pg = GunplaID.encode(machineID: 7, grade: .pg)
        let active = MonState(baseID: pg, pathIDs: [pg], stageIndex: 0, usedAtStage: 0,
                              rarity: .rare, totalForms: 1)
        let complete = try store(owning: zetaWithoutPGZetaGundam, active: active)
        XCTAssertTrue(complete.earnedDexBadges.contains(.series("zeta")))
        XCTAssertTrue(complete.state.notifiedDexCompletions.contains("series.zeta"))
    }

    func testLegacyImportSeedsExistingCompletionsBeforeANewHatch() async throws {
        try await assertLegacyImportTracksTheNextCompletion(existingFirst: true)
    }

    func testLegacyImportWithoutEarnedBadgesStillEnablesFutureCompletions() async throws {
        try await assertLegacyImportTracksTheNextCompletion(existingFirst: false)
    }

    private func assertLegacyImportTracksTheNextCompletion(existingFirst: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-dex-import-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("companion-state.json")
        let suite = "ptb-dex-import-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1.0, forKey: "growthDifficulty")

        var legacy = CompanionState()
        var owned: [Int: [GunplaGrade]?] = zetaWithoutPGZetaGundam
        if existingFirst {
            for machine in catalog.machines where machine.series == "first" && !machine.isVariant {
                owned[machine.id] = .some(nil)
            }
        }
        legacy.dex = entries(owned)
        legacy.eggUsage = PokemonBalance.eggHatchThreshold
        // The final missing Zeta cell (Zeta Gundam PG), ready to hatch after import.
        legacy.pendingHatchID = GunplaID.encode(machineID: 7, grade: .pg)
        let data = try SaveTransfer.encode(state: legacy, appVersion: "2.5.0", deviceName: "Old Mac", now: Date())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var oldState = try XCTUnwrap(json["state"] as? [String: Any])
        oldState.removeValue(forKey: "notifiedDexCompletions")
        oldState.removeValue(forKey: "dexCompletionsSeeded")
        json["state"] = oldState
        let envelope = try SaveTransfer.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(envelope.state.dexCompletionsSeeded, "the exported save predates completion tracking")

        let store = CompanionStore(provider: catalog, fileURL: url, defaults: defaults)
        try store.applySave(envelope, todayTokensByProvider: ["test": 0], todayDate: "2026-11-05", hasUsageData: true)
        let preexisting: Set<String> = existingFirst ? ["series.first"] : []
        XCTAssertTrue(store.state.dexCompletionsSeeded)
        XCTAssertEqual(store.state.notifiedDexCompletions, preexisting,
                       "imported completions are seeded rather than announced again")
        let persisted = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: url))
        XCTAssertTrue(persisted.dexCompletionsSeeded, "even an empty seed must persist during import")

        await store.hatchIfNeeded()
        XCTAssertEqual(store.state.active?.baseID, GunplaID.encode(machineID: 7, grade: .pg))
        XCTAssertTrue(store.earnedDexBadges.contains(.series("zeta")))
        XCTAssertEqual(store.state.notifiedDexCompletions, preexisting.union(["series.zeta"]),
                       "a newly completed series is announced in the same session without restarting")
        let after = store.state.notifiedDexCompletions
        store.checkDexCompletions()
        XCTAssertEqual(store.state.notifiedDexCompletions, after, "completion is announced once")
    }
}
