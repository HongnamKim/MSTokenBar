import XCTest
@testable import PokeTokenBar

@MainActor
final class SeriesBoxStoreTests: XCTestCase {
    private typealias F = PreorderFixture

    private func buildingStore(_ machineID: Int = PreorderFixture.zaku, dex: [DexEntry] = [],
                               usedSinceInstall: Int = 0) throws -> CompanionStore {
        var st = CompanionState()
        st.active = F.building(machineID)
        st.dex = dex
        st.usedSinceInstall = usedSinceInstall
        return try F.store(st)
    }
    private func machines(in series: String) -> [MachineRecord] { F.catalog.machines.filter { $0.series == series } }

    func test_seriesBoxReplacesTheBuildAndOnlyOpensThatSeries() async throws {
        let s = try buildingStore()
        let spent = s.state.spentTokens
        XCTAssertTrue(s.buySeriesBox("0080"))
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.eggSeries, "0080")
        XCTAssertEqual(s.eggSeriesID, "0080")
        XCTAssertNil(s.state.eggTier)
        XCTAssertEqual(s.state.spentTokens - spent, s.seriesBoxPrice("0080"))
        XCTAssertTrue(s.state.dex.contains { F.machineID($0.baseID) == F.zaku && $0.releasedAt != nil })
        await F.openBox(s)
        XCTAssertEqual(F.catalog.machine(speciesID: try XCTUnwrap(s.state.active).baseID)?.series, "0080")
        XCTAssertNil(s.state.eggSeries)
        XCTAssertNil(s.eggSeriesID)
    }

    func test_whatBlocksASeriesBox() throws {
        XCTAssertFalse(try F.store().canBuySeriesBox("0080"), "no build to stop")
        let s = try buildingStore()
        XCTAssertFalse(s.canBuySeriesBox("nope"))
        let done = try buildingStore(dex: machines(in: "0080").map { F.finished($0.id) })
        XCTAssertNil(done.seriesBoxRemainingCounts["0080"])
        XCTAssertFalse(done.canBuySeriesBox("0080"))
        XCTAssertFalse(try buildingStore(usedSinceInstall: 1).canBuySeriesBox("0080"))
    }

    func test_remainingCountsCustomUnits() throws {
        let s = try buildingStore(F.gouf)
        XCTAssertEqual(s.seriesBoxRemainingCounts["first"], machines(in: "first").count)
        let after = try buildingStore(F.gouf, dex: [F.finished(F.charZaku)])
        XCTAssertEqual(after.seriesBoxRemainingCounts["first"], machines(in: "first").count - 1)
    }

    func test_priceIsTheLowestRaritysTierBoxPrice() throws {
        let s = try buildingStore()
        let expected: [String: Rarity] = ["first": .common, "narrative": .uncommon, "victory": .rare,
                                          "beltorchika-children": .legendary]
        for (series, rarity) in expected { XCTAssertEqual(s.seriesBoxPrice(series), s.price(of: .egg(rarity)), series) }
    }

    func test_seriesBoxChargesTheScaledPrice() throws {
        let s = try buildingStore()
        s.setShopDifficulty(0.5)
        XCTAssertEqual(s.seriesBoxPrice("first"), PokemonBalance.scaled(FreshEgg.price(guaranteeing: .common), by: 0.5))
        let spent = s.state.spentTokens
        XCTAssertTrue(s.buySeriesBox("first"))
        XCTAssertEqual(s.state.spentTokens - spent, s.seriesBoxPrice("first"))
    }

    func test_preorderComesFirstInASeriesBox() async throws {
        var st = CompanionState()
        st.eggSeries = "0080"
        st.preorder = Preorder(machineID: F.gouf, boxesOpened: 3)
        let s = try F.store(st)
        await F.openBox(s)
        XCTAssertEqual(F.machineID(s.state.active?.baseID), F.gouf)
        XCTAssertNil(s.state.preorder)
        XCTAssertNil(s.state.eggSeries)
    }
}
