import XCTest
@testable import PokeTokenBar

@MainActor
final class ToolSetTests: XCTestCase {
    private let catalog = MachineCatalog.shared
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func store(used: Int, spent: Int = 0, inventory: [String: Int] = [:], dex: [DexEntry] = [],
                       activeJSON: String? = nil, pending: Int? = nil) throws -> CompanionStore {
        var seeded = CompanionState()
        seeded.pendingHatchID = pending
        seeded.installBaselineSet = true
        seeded.usedSinceInstall = used
        seeded.spentTokens = spent
        seeded.inventory = inventory
        seeded.dex = dex
        if let activeJSON { seeded.active = try JSONDecoder().decode(MonState.self, from: Data(activeJSON.utf8)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("toolset-\(UUID().uuidString).json")
        try JSONEncoder().encode(seeded).write(to: url)
        let fixedNow = now
        return CompanionStore(provider: catalog, clock: { fixedNow }, fileURL: url,
                              rng: SeededRNG(seed: 1),
                              defaults: UserDefaults(suiteName: "toolset-\(UUID().uuidString)")!)
    }

    private let activeCommon = "{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":0,"
        + "\"rarity\":\"common\",\"totalForms\":1,\"isShiny\":false}"

    // MARK: pure rules

    func test_denominatorsByLevel() {
        XCTAssertEqual((0...4).map { ToolSet.shinyDenominator(toolLevel: $0) }, [32, 26, 21, 16, 12])
    }

    func test_levelCountsOnlyContiguousPrefix() {
        XCTAssertEqual(ToolSet.level(inventory: ["maskingTape": 1, "paintSet": 1]), 1)
        XCTAssertEqual(ToolSet.level(inventory: ["panelLinePen": 1]), 0)
        XCTAssertEqual(ToolSet.level(inventory: [:]), 0)
        XCTAssertEqual(ToolSet.level(inventory: ["maskingTape": 1, "panelLinePen": 1, "paintSet": 1, "airbrush": 1]), 4)
    }

    func test_nextPurchasableFollowsOrder() {
        XCTAssertEqual(ToolSet.nextPurchasable(inventory: [:]), .maskingTape)
        XCTAssertEqual(ToolSet.nextPurchasable(inventory: ["maskingTape": 1]), .panelLinePen)
        XCTAssertNil(ToolSet.nextPurchasable(inventory: ["maskingTape": 1, "panelLinePen": 1, "paintSet": 1, "airbrush": 1]))
    }

    func test_itemConstants() {
        XCTAssertEqual(ToolSet.order, [.maskingTape, .panelLinePen, .paintSet, .airbrush])
        XCTAssertEqual(ToolSet.order.compactMap { ToolSet.prices[$0] }, [1_000_000_000, 1_500_000_000, 2_000_000_000, 3_000_000_000])
        XCTAssertEqual(ToolSet.order.map(\.fallbackEmoji), ["🩹", "🖊️", "🎨", "💨"])
        XCTAssertEqual(ItemKind.rareCandy.fallbackEmoji, "🧽")
        XCTAssertEqual(ItemKind.rareCandy.rawValue, "rareCandy")
        for kind in ToolSet.order { XCTAssertTrue(kind.isPassive) }
        XCTAssertFalse(ItemKind.rareCandy.isPassive)
        XCTAssertEqual(ItemKind.allCases.count, 5)
    }

    // MARK: store

    func test_toolsMustBeBoughtInOrder() throws {
        let s = try store(used: 10_000_000_000)
        XCTAssertFalse(s.canBuy(.panelLinePen))
        XCTAssertFalse(s.canBuy(.airbrush))
        XCTAssertFalse(s.buy(.paintSet))
        XCTAssertTrue(s.canBuy(.maskingTape))
        XCTAssertTrue(s.buy(.maskingTape))
        XCTAssertTrue(s.canBuy(.panelLinePen))
        XCTAssertEqual(s.toolLevel, 1)
        XCTAssertEqual(s.shinyDenominator, 26)
    }

    /// The box pre-rolls its machine (variant or not) with the odds of the moment. A tool bought while waiting
    /// must re-roll it, so the hatch uses — and its notification quotes — the new odds.
    func test_buyingToolInBoxStateDropsThePreRoll() throws {
        let s = try store(used: 10_000_000_000, pending: GunplaID.encode(machineID: 2, grade: .sd))
        XCTAssertTrue(s.isEgg)
        XCTAssertTrue(s.buy(.maskingTape))
        XCTAssertNil(s.state.pendingHatchID)
    }

    func test_buyingSpongeInBoxStateKeepsThePreRoll() throws {
        let pending = GunplaID.encode(machineID: 2, grade: .sd)
        let s = try store(used: 10_000_000_000, pending: pending)
        XCTAssertTrue(s.buy(.rareCandy))
        XCTAssertEqual(s.state.pendingHatchID, pending)
    }

    func test_toolNeedsEnoughTokens() throws {
        XCTAssertFalse(try store(used: 999_999_999).canBuy(.maskingTape))
        XCTAssertTrue(try store(used: 1_000_000_000).canBuy(.maskingTape))
    }

    func test_ownedToolCannotBeBoughtAgain() throws {
        let s = try store(used: 10_000_000_000, inventory: ["maskingTape": 1])
        XCTAssertFalse(s.canBuy(.maskingTape))
        XCTAssertEqual(s.maxBuyCount(.maskingTape), 0)
        XCTAssertFalse(s.buy(.maskingTape))
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    func test_allToolsRaiseOddsToMax() throws {
        let s = try store(used: 20_000_000_000)
        for kind in ToolSet.order { XCTAssertTrue(s.buy(kind), "\(kind)") }
        XCTAssertEqual(s.toolLevel, 4)
        XCTAssertEqual(s.shinyDenominator, 12)
        XCTAssertEqual(s.state.spentTokens, 7_500_000_000)
    }

    func test_ownedToolsSinkInShopList() throws {
        let s = try store(used: 0, inventory: ["maskingTape": 1])
        XCTAssertEqual(s.purchasableItems, [.rareCandy, .panelLinePen, .paintSet, .airbrush, .maskingTape])
        XCTAssertTrue(s.isToolLocked(.paintSet))
        XCTAssertFalse(s.isToolLocked(.panelLinePen))
        XCTAssertFalse(s.isToolLocked(.maskingTape))
    }

    func test_spongeKeepsRareCandyGrantRules() throws {
        // rawValue is unchanged, so saved inventories and grant rules apply to the sponge as before.
        let s = try store(used: 0, inventory: ["rareCandy": 3])
        XCTAssertEqual(s.rareCandyCount, 3)
        XCTAssertEqual(s.itemCount(.rareCandy), 3)
        XCTAssertEqual(ItemKind.rareCandy.shopPrice, RareCandy.price)
    }

    func test_removedItemsInSavedInventoryAreIgnored() throws {
        let s = try store(used: 0, inventory: ["mint": 2, "shinyCharm": 1, "rareCandy": 1])
        XCTAssertEqual(s.ownedItems.map(\.kind), [.rareCandy])
        XCTAssertEqual(s.toolLevel, 0)
        XCTAssertEqual(s.shinyDenominator, 32)
    }

    func test_rareBoxDisabledWhenTierExhausted() throws {
        let graduated = catalog.machines.filter { $0.rarity.sortRank >= Rarity.rare.sortRank }.map { machine in
            let ids = machine.grades.map { GunplaID.encode(machineID: machine.id, grade: $0) }
            return DexEntry(baseID: ids[0], finalID: ids[ids.count - 1], chainOrder: ids,
                            rarity: machine.rarity, caughtAt: now, releasedAt: nil)
        }
        XCTAssertFalse(graduated.isEmpty)
        let s = try store(used: 20_000_000_000, dex: graduated, activeJSON: activeCommon)
        XCTAssertTrue(s.hasActive)
        XCTAssertFalse(s.canBuyEgg(.rare))
        XCTAssertTrue(s.isEggTierExhausted(.rare))
        XCTAssertFalse(s.buyEgg(.rare))
        XCTAssertEqual(s.state.spentTokens, 0)
        XCTAssertTrue(s.canBuyEgg(nil))
        XCTAssertFalse(s.isEggTierExhausted(nil))
    }

    func test_rareBoxEnabledWhenTierHasCandidates() throws {
        let s = try store(used: 20_000_000_000, activeJSON: activeCommon)
        XCTAssertTrue(s.canBuyEgg(.rare))
        XCTAssertTrue(s.canBuyEgg(.uncommon))
    }
}
