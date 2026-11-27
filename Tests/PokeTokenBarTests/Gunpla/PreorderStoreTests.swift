import XCTest
@testable import PokeTokenBar

@MainActor
final class PreorderStoreTests: XCTestCase {
    private typealias F = PreorderFixture

    private func state(preorder: Preorder? = nil, pending: Int? = nil, tier: Rarity? = nil) -> CompanionState {
        var s = CompanionState()
        s.preorder = preorder
        s.pendingHatchID = pending
        s.eggTier = tier
        return s
    }
    private func opened(_ s: CompanionStore) throws -> Int {
        try XCTUnwrap(F.machineID(s.state.active?.baseID))
    }

    // MARK: rolling and counting

    func test_fourthBoxBringsTheTargetAndEndsThePreorder() async throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.gouf, boxesOpened: 3)))
        await F.openBox(s)
        XCTAssertEqual(try opened(s), F.gouf)
        XCTAssertNil(s.state.preorder)
    }

    func test_otherMachineCountsOneBox() async throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.gouf, boxesOpened: 0), pending: F.id(F.zaku, .sd)))
        await F.openBox(s)
        XCTAssertEqual(try opened(s), F.zaku)
        XCTAssertEqual(s.state.preorder, Preorder(machineID: F.gouf, boxesOpened: 1))
    }

    func test_targetFromTheBoxsOwnRollEndsThePreorder() async throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.gouf, boxesOpened: 1), pending: F.id(F.gouf, .sd)))
        await F.openBox(s)
        XCTAssertEqual(try opened(s), F.gouf)
        XCTAssertNil(s.state.preorder)
    }

    func test_arrivalUsesThePreorderCopyEvenForACustomUnitOrPrayers() async throws {
        var st = state(preorder: Preorder(machineID: F.charZaku, boxesOpened: 3))
        st.eggPrayers = PrayerRecord(count: 5)
        let s = try F.store(st)
        await F.openBox(s)
        let active = try XCTUnwrap(s.state.active)
        let name = try XCTUnwrap(s.currentLine).localizedName(active.baseID, s.state.language)
        XCTAssertEqual(s.latestEvent?.text, s.l.notifPreorderBody(name))
        XCTAssertEqual(active.prayers?.count, 5, "prayers still move onto the machine")
    }

    func test_rareBoxDeliversACommonTarget() async throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.zaku, boxesOpened: 3), tier: .rare))
        await F.openBox(s)
        XCTAssertEqual(try opened(s), F.zaku)
        XCTAssertNil(s.state.preorder)
        XCTAssertNil(s.state.eggTier)
    }

    func test_preRollDiscardedByTheTierGateIsNotCounted() async throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.gouf, boxesOpened: 1), pending: F.id(F.zaku, .sd),
                                  tier: .rare))
        await F.openBox(s)
        let machine = try opened(s)
        XCTAssertNotEqual(machine, F.zaku, "the common pre-roll was discarded")
        if machine == F.gouf { XCTAssertNil(s.state.preorder) } else { XCTAssertEqual(s.state.preorder?.boxesOpened, 2) }
    }

    func test_toolPurchaseDropsThePreRollWithoutCounting() throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.gouf, boxesOpened: 2), pending: F.id(F.zaku, .sd)))
        XCTAssertTrue(s.buy(.maskingTape))
        XCTAssertNil(s.state.pendingHatchID)
        XCTAssertEqual(s.state.preorder?.boxesOpened, 2)
    }

    func test_unservablePreRollIsDroppedWithoutCounting() async throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.gouf, boxesOpened: 2), pending: 25))
        F.use(s, 0)
        F.use(s, 1)   // a tick below the threshold runs the prefetch, which drops 25
        let deadline = Date().addingTimeInterval(2)
        while s.state.pendingHatchID == 25, Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertNotEqual(s.state.pendingHatchID, 25)
        XCTAssertEqual(s.state.preorder?.boxesOpened, 2)
    }

    // MARK: buying

    func test_buyingWhileHoldingABoxRerollsIt() throws {
        let s = try F.store(state(pending: F.id(F.zaku, .sd)))
        let spent = s.state.spentTokens
        XCTAssertTrue(s.buyPreorder(F.gouf))
        XCTAssertEqual(s.state.preorder, Preorder(machineID: F.gouf, boxesOpened: 0))
        XCTAssertNil(s.state.pendingHatchID)
        XCTAssertEqual(s.state.spentTokens - spent, s.price(of: .egg(.uncommon)))
    }

    func test_buyPreorderWhileBuildingKeepsTheBuild() throws {
        var st = CompanionState()
        st.active = F.building(F.zaku)
        let s = try F.store(st)
        XCTAssertTrue(s.buyPreorder(F.gouf))
        XCTAssertEqual(F.machineID(s.state.active?.baseID), F.zaku)
        XCTAssertEqual(s.state.preorder?.boxesOpened, 0)
    }

    func test_whatCannotBePreordered() throws {
        var st = CompanionState()
        st.active = F.building(F.zaku)
        st.dex = [F.finished(F.rx78)]
        let s = try F.store(st)
        XCTAssertFalse(s.canBuyPreorder(F.zaku), "being built")
        XCTAssertFalse(s.canBuyPreorder(F.rx78), "complete")
        XCTAssertFalse(s.canBuyPreorder(9_999), "unknown")
        XCTAssertTrue(s.buyPreorder(F.gouf))
        XCTAssertFalse(s.canBuyPreorder(F.charZaku), "one at a time")
        XCTAssertFalse(s.buyPreorder(F.charZaku))

        var poor = CompanionState()
        poor.usedSinceInstall = 1
        XCTAssertFalse(try F.store(poor).canBuyPreorder(F.gouf))
    }

    func test_buyPreorderChargesTheScaledPrice() throws {
        let s = try F.store()
        s.setShopDifficulty(2.0)
        let spent = s.state.spentTokens
        let gouf = try XCTUnwrap(F.catalog.machine(id: F.gouf))
        XCTAssertEqual(s.preorderPrice(gouf), PokemonBalance.scaled(FreshEgg.price(guaranteeing: .uncommon), by: 2.0))
        XCTAssertTrue(s.buyPreorder(F.gouf))
        XCTAssertEqual(s.state.spentTokens - spent, s.preorderPrice(gouf))
    }

    func test_priceFollowsTheTargetsRarity() throws {
        let s = try F.store()
        for (machine, rarity) in [(F.zaku, Rarity.common), (F.gouf, .uncommon), (F.rx78, .rare), (F.nu, .legendary)] {
            XCTAssertEqual(s.preorderPrice(try XCTUnwrap(F.catalog.machine(id: machine))), s.price(of: .egg(rarity)))
        }
        XCTAssertEqual(s.shopPriceRange, s.price(of: .egg(.common))...s.price(of: .egg(.legendary)))
    }

    func test_statusesAndCandidates() throws {
        var st = CompanionState()
        st.active = F.building(F.zaku)
        st.dex = [F.finished(F.rx78)]
        let s = try F.store(st)
        let statuses = s.preorderPickStatuses
        XCTAssertEqual(statuses.count, F.catalog.machines.count)
        XCTAssertEqual(statuses[F.zaku], .building)
        XCTAssertEqual(statuses[F.rx78], .complete)
        XCTAssertEqual(statuses[F.gouf], .available)
        XCTAssertTrue(s.hasPreorderCandidates)

        var done = CompanionState()
        done.dex = F.catalog.machines.map { F.finished($0.id) }
        XCTAssertFalse(try F.store(done).hasPreorderCandidates)
    }
}
