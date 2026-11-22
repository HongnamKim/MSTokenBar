import XCTest
@testable import PokeTokenBar

private struct GrowthProfileProvider: PokeProviding, PokemonDetailProviding {
    var forms = 3
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        var node = EvoNode(speciesID: forms, children: [])
        if forms > 1 {
            for id in (1..<forms).reversed() { node = EvoNode(speciesID: id, children: [node]) }
        }
        return EvoLine(baseID: 1, tree: node, rarity: .common,
                       names: Dictionary(uniqueKeysWithValues: (1...forms).map { ($0, ["en": "P\($0)"]) }))
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "p", height: 1, weight: 1,
                       baseExperience: nil, genderRate: -1, types: [], baseStats: [:], abilities: [],
                       moves: [PokemonMoveOption(name: "final-\(speciesID)", learnMethods: [
                        PokemonMoveLearnMethod(method: "level-up", level: 100)])])
    }
}

@MainActor
final class ProfileGrowthIntegrationTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }
    private func fixture(_ state: CompanionState = CompanionState(), difficulty: Double = 1,
                         forms: Int = 3) throws -> (CompanionStore, URL, UserDefaults) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("profile-integration-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let file = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let suite = "profile-integration-\(UUID())"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(difficulty, forKey: "growthDifficulty")
        return (CompanionStore(provider: GrowthProfileProvider(forms: forms), fileURL: file,
                               dittoDisguiseRollingEnabled: false, defaults: defaults), file, defaults)
    }

    func testLegacyStageMigrationUsesBoostAndDifficulty() throws {
        var seed = CompanionState()
        seed.active = MonState(baseID: 1, pathIDs: [1, 2], plannedPathIDs: [1, 2, 3],
                               stageIndex: 1, usedAtStage: 6_250_000, rarity: .common,
                               totalForms: 3, hasGrowthBoost: true)
        let (s, _, _) = try fixture(seed, difficulty: 0.1)
        XCTAssertEqual(s.state.active?.profile?.growthTokens, 250_000_000)
        XCTAssertEqual(s.state.active?.profile?.level, 36)
    }

    func testOfflineOverflowCatchesUpWhenLineLoads() async throws {
        var seed = CompanionState()
        seed.active = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1, 2, 3],
                               stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)
        let (s, _, _) = try fixture(seed, difficulty: 0.1)
        s.applyUsage(75_000_000)
        XCTAssertEqual(s.state.active?.usedAtStage, 75_000_000)
        s.update(todayTokensByProvider: [:], todayDate: "day", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: false)
        for _ in 0..<200 {
            if s.state.active == nil { break }
            await Task.yield()
        }
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.dex.last?.profile?.level, 100)
    }

}
