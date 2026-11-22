import XCTest
@testable import PokeTokenBar

private struct MockPokeProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class DexSearchAndFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func createTestStore() -> CompanionStore {
        let entryBulbasaur = DexEntry(
            id: "entry-1",
            baseID: 1,
            finalID: 3,
            chainOrder: [1, 2, 3],
            rarity: .common,
            caughtAt: Date(timeIntervalSince1970: 1_700_000_100),
            isShiny: false,
            names: [
                1: ["ko": "이상해씨", "en": "Bulbasaur", "fr": "Bulbizarre"],
                2: ["ko": "이상해풀", "en": "Ivysaur", "fr": "Herbizarre"],
                3: ["ko": "이상해꽃", "en": "Venusaur", "fr": "Florizarre"]
            ]
        )
        let entryPikachu = DexEntry(
            id: "entry-2",
            baseID: 25,
            finalID: 26,
            chainOrder: [25, 26],
            rarity: .rare,
            caughtAt: Date(timeIntervalSince1970: 1_700_000_200),
            isShiny: true,
            names: [
                25: ["ko": "피카츄", "en": "Pikachu", "fr": "Pikachu"],
                26: ["ko": "라이츄", "en": "Raichu", "fr": "Raichu"]
            ]
        )
        let entryMewtwo = DexEntry(
            id: "entry-3",
            baseID: 150,
            finalID: 150,
            chainOrder: [150],
            rarity: .legendary,
            caughtAt: Date(timeIntervalSince1970: 1_700_000_300),
            isShiny: false,
            names: [
                150: ["ko": "뮤츠", "en": "Mewtwo", "fr": "Mewtwo"]
            ]
        )

        return makeStore(dex: [entryBulbasaur, entryPikachu, entryMewtwo])
    }

    /// Gunpla save: Gundam (1) SD+HG, Zaku II (2) HG, Char's Zaku II (3, variant) HG,
    /// Zeta Gundam (7) HG, Nu Gundam (8) SD.
    private func createHangarStore(language: AppLanguage = .en) -> CompanionStore {
        let owned: [(Int, [GunplaGrade])] = [(1, [.sd, .hg]), (2, [.hg]), (3, [.hg]), (7, [.hg]), (8, [.sd])]
        let dex = owned.map { machineID, grades in
            let machine = MachineCatalog.shared.machine(id: machineID)!
            let ids = grades.map { GunplaID.encode(machineID: machineID, grade: $0) }
            return DexEntry(baseID: ids[0], finalID: ids[ids.count - 1], chainOrder: ids, rarity: machine.rarity,
                            caughtAt: now, isShiny: machine.isVariant)
        }
        return makeStore(dex: dex, language: language)
    }

    private func makeStore(dex: [DexEntry], active: MonState? = nil, language: AppLanguage = .en) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dex-search-\(UUID().uuidString).json")
        var state = CompanionState()
        state.dex = dex
        state.active = active
        state.language = language
        try? JSONEncoder().encode(state).write(to: url)

        return CompanionStore(provider: MockPokeProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 42))
    }

    /// Sprite → Pokédex page links. Every dex species (graduated chains and the raising Pokémon's
    /// reached stages) links to its dex cell; an unreached evolution and an uncaught species do
    /// not, so their sprites stay inert.
    func testDexLinkTargetsCoverOnlySpeciesInTheDex() {
        let raising = MonState(baseID: 4, pathIDs: [4, 5], plannedPathIDs: [4, 5, 6], stageIndex: 1,
                               usedAtStage: 0, rarity: .common, totalForms: 3)
        let store = makeStore(dex: createTestStore().state.dex, active: raising)

        let links = store.dexLinkTargets
        XCTAssertEqual(links[1], "1")
        XCTAssertEqual(links[26], "26")
        XCTAssertEqual(links[5], "5", "the raising Pokémon's current form links (it has a RAISING dex cell)")
        XCTAssertEqual(links[4], "4", "a reached earlier stage links")
        XCTAssertNil(links[6], "an unreached evolution has no dex page")
        XCTAssertNil(links[999], "an uncaught species has no dex page")
        XCTAssertEqual(Set(links.keys), Set(store.dexSpecies.map(\.id)))
        for (id, collectionID) in links {
            XCTAssertEqual(store.dexSpecies.first { $0.collectionID == collectionID }?.id, id,
                           "every link resolves to the detail page CollectionView would open")
        }
    }

    /// An egg has no species, so the Home header sprite gets no link target.
    func testEggHasNoDexLinkTarget() {
        let store = makeStore(dex: createTestStore().state.dex)
        XCTAssertTrue(store.isEgg)
        XCTAssertNil(store.currentSpeciesID.flatMap { store.dexLinkTargets[$0] })
    }

    /// Hangar search: the machine name in the current language or its model number, ignoring case.
    func testHangarSearchByNameAndModelNumber() {
        let store = createHangarStore()
        func ids(_ query: String) -> [Int] { store.filteredHangarCells(query: query).map(\.machineID) }

        XCTAssertEqual(ids("Zaku"), [2, 3])
        XCTAssertEqual(ids("zeta"), [7], "case-insensitive")
        XCTAssertEqual(ids("nu gundam"), [8])
        XCTAssertEqual(ids("RX-93"), [8], "model number")
        XCTAssertEqual(ids("rx-7"), [1], "partial model number, any case")
        XCTAssertEqual(ids("MS-06"), [2, 3])
        XCTAssertEqual(ids("자쿠"), [], "other languages' names are not searched")
        XCTAssertEqual(ids("MissingNo"), [])
        XCTAssertEqual(ids("").count, store.hangarCells.count, "a blank query filters nothing")

        let korean = createHangarStore(language: .ko)
        XCTAssertEqual(korean.filteredHangarCells(query: "자쿠").map(\.machineID), [2, 3])
        XCTAssertEqual(korean.filteredHangarCells(query: "Zaku").map(\.machineID), [])
    }

    /// Regression: the Catch Log used `localizedCaseInsensitiveContains`, which keeps accents, so
    /// "flabebe" missed Flabébé although the PR promised diacritic-insensitive name search.
    func testNameSearchIgnoresCaseAndDiacriticsInCatchLog() {
        let flabebe = DexEntry(
            id: "entry-flabebe",
            baseID: 669,
            finalID: 669,
            chainOrder: [669],
            rarity: .common,
            caughtAt: Date(timeIntervalSince1970: 1_700_000_400),
            names: [669: ["ko": "플라베베", "en": "Flabébé", "fr": "Flabébé"]]
        )
        let pikachu = DexEntry(
            id: "entry-pikachu",
            baseID: 25,
            finalID: 25,
            chainOrder: [25],
            rarity: .rare,
            caughtAt: Date(timeIntervalSince1970: 1_700_000_500),
            names: [25: ["ko": "피카츄", "en": "Pikachu", "fr": "Pikachu"]]
        )
        let store = makeStore(dex: [flabebe, pikachu])

        for query in ["flabebe", "FLABEBE", "Flabébé", "flabébe"] {
            XCTAssertEqual(store.filteredDexEntries(query: query).map(\.id), ["entry-flabebe"], "Catch Log: \(query)")
        }
    }

    func testHangarFilterByVariantRarityAndSeries() {
        let store = createHangarStore()
        func ids(rarity: Rarity? = nil, variantOnly: Bool = false, series: String? = nil) -> [Int] {
            store.filteredHangarCells(rarity: rarity, variantOnly: variantOnly, series: series).map(\.machineID)
        }

        XCTAssertEqual(ids(variantOnly: true), [3])
        XCTAssertEqual(ids(rarity: .legendary), [8])
        XCTAssertEqual(ids(rarity: .rare), [1, 3, 7])
        XCTAssertEqual(ids(rarity: .common), [2])
        XCTAssertEqual(ids(rarity: .rare, variantOnly: true), [3])
        XCTAssertEqual(ids(rarity: .legendary, variantOnly: true), [])
        XCTAssertEqual(ids(series: "first"), [1, 2, 3])
        XCTAssertEqual(ids(rarity: .rare, series: "zeta"), [7])
    }

    func testHangarSorting() {
        let store = createHangarStore()
        func ids(_ sort: CompanionStore.DexSortOption) -> [Int] { store.filteredHangarCells(sort: sort).map(\.machineID) }

        XCTAssertEqual(ids(.numberAsc), [1, 2, 3, 7, 8], "series order, then machine id")
        XCTAssertEqual(ids(.numberDesc), [8, 7, 3, 2, 1])
        // Char's Zaku II, Gundam, Nu Gundam, Zaku II, Zeta Gundam
        XCTAssertEqual(ids(.nameAsc), [3, 1, 8, 2, 7])
        XCTAssertEqual(ids(.nameDesc), [7, 2, 8, 1, 3])
        XCTAssertEqual(ids(.rarityDesc), [8, 1, 3, 7, 2], "rarity, then hangar order")
    }

    func testCatchLogSearchAndFilters() {
        let store = createTestStore()

        // Search by chain species ID
        let matchChain = store.filteredDexEntries(query: "25")
        XCTAssertEqual(matchChain.count, 1)
        XCTAssertEqual(matchChain.first?.baseID, 25)
        // Partial number with the # prefix
        XCTAssertEqual(store.filteredDexEntries(query: "#15").map(\.id), ["entry-3"])

        // Search by name
        let matchName = store.filteredDexEntries(query: "Raichu")
        XCTAssertEqual(matchName.count, 1)
        XCTAssertEqual(matchName.first?.baseID, 25)

        // Shiny only
        let shinies = store.filteredDexEntries(shinyOnly: true)
        XCTAssertEqual(shinies.count, 1)
        XCTAssertEqual(shinies.first?.baseID, 25)

        // Rarity
        let legendaryEntries = store.filteredDexEntries(rarity: .legendary)
        XCTAssertEqual(legendaryEntries.count, 1)
        XCTAssertEqual(legendaryEntries.first?.baseID, 150)
    }

    func testCatchLogSorting() {
        let store = createTestStore()

        // Recent first
        let recent = store.filteredDexEntries(sort: .recentFirst)
        XCTAssertEqual(recent.first?.finalID, 150) // caughtAt 300 is most recent
        XCTAssertEqual(recent.last?.finalID, 3)    // caughtAt 100 is oldest

        // Oldest first
        let oldest = store.filteredDexEntries(sort: .oldestFirst)
        XCTAssertEqual(oldest.first?.finalID, 3)
        XCTAssertEqual(oldest.last?.finalID, 150)

        // Number asc
        let numAsc = store.filteredDexEntries(sort: .numberAsc)
        XCTAssertEqual(numAsc.map(\.finalID), [3, 26, 150])

        // Number desc
        let numDesc = store.filteredDexEntries(sort: .numberDesc)
        XCTAssertEqual(numDesc.map(\.finalID), [150, 26, 3])

        // Rarity desc
        let rarityDesc = store.filteredDexEntries(sort: .rarityDesc)
        XCTAssertEqual(rarityDesc.map(\.rarity), [.legendary, .rare, .common])
    }

    func testSortOptionLabelsExistInAllLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            for option in CompanionStore.DexSortOption.allCases {
                let label = l.label(for: option)
                XCTAssertFalse(label.isEmpty, "Missing DexSortOption label for \(option) in \(lang)")
            }
            for option in CompanionStore.CatchLogSortOption.allCases {
                let label = l.label(for: option)
                XCTAssertFalse(label.isEmpty, "Missing CatchLogSortOption label for \(option) in \(lang)")
            }
            XCTAssertFalse(l.dexSearchPlaceholder.isEmpty)
            XCTAssertFalse(l.sortTitle.isEmpty)
            XCTAssertFalse(l.filterShinyOnly.isEmpty)
            XCTAssertFalse(l.noSearchResults.isEmpty)
            XCTAssertFalse(l.clearFilters.isEmpty)
        }
    }
}
