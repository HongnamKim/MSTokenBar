import XCTest
@testable import PokeTokenBar

@MainActor
final class PreorderPickCellsTests: XCTestCase {
    private typealias F = PreorderFixture

    private func store(dex: [DexEntry] = []) throws -> CompanionStore {
        var st = CompanionState()
        st.language = .ko
        st.dex = dex
        return try F.store(st)
    }

    func test_listsEveryMachineIncludingUnbuiltCustomUnits() throws {
        let s = try store()
        let cells = s.preorderPickCells()
        XCTAssertEqual(Set(cells.map(\.machineID)), Set(F.catalog.machines.map(\.id)))
        XCTAssertTrue(cells.contains { $0.machineID == F.charZaku && !$0.isBuilt })
        XCTAssertFalse(s.filteredHangarCells(includeUnbuilt: true).contains { $0.machineID == F.charZaku },
                       "the normal hangar still hides unbuilt custom units")
    }

    func test_rarityAndCustomFiltersKeepUnbuiltCells() throws {
        let s = try store()
        let rare = s.preorderPickCells(rarity: .rare)
        XCTAssertTrue(rare.contains { $0.machineID == F.rx78 && !$0.isBuilt })
        XCTAssertTrue(rare.allSatisfy { F.catalog.machine(id: $0.machineID)?.rarity == .rare })
        let customs = s.preorderPickCells(variantOnly: true)
        XCTAssertTrue(customs.contains { $0.machineID == F.charZaku })
        XCTAssertTrue(customs.allSatisfy(\.isVariant))
    }

    func test_nameSearchFindsUnbuiltMachines() throws {
        let s = try store()
        XCTAssertTrue(s.preorderPickCells(query: "구프").contains { $0.machineID == F.gouf })
        XCTAssertFalse(s.filteredHangarCells(query: "구프", includeUnbuilt: true).contains { $0.machineID == F.gouf },
                       "the normal hangar still hides unbuilt names")
    }

    func test_seriesFilter() throws {
        let cells = try store().preorderPickCells(series: "0080")
        XCTAssertEqual(cells.count, F.catalog.machines.filter { $0.series == "0080" }.count)
        XCTAssertTrue(cells.allSatisfy { F.catalog.machine(id: $0.machineID)?.series == "0080" })
    }

    func test_builtCellsKeepTheirGrades() throws {
        let sd = F.id(F.zaku, .sd), hg = F.id(F.zaku, .hg)
        let entry = DexEntry(baseID: sd, finalID: hg, chainOrder: [sd, hg], rarity: .common, caughtAt: F.now,
                             releasedAt: F.now)
        let cell = try XCTUnwrap(try store(dex: [entry]).preorderPickCells().first { $0.machineID == F.zaku })
        XCTAssertEqual(cell.ownedGrades, [.sd, .hg])
    }

    func test_groupStatus() {
        XCTAssertEqual(PreorderPickStatus.combined([.complete, .available]), .available)
        XCTAssertEqual(PreorderPickStatus.combined([.complete, .complete]), .complete)
        XCTAssertEqual(PreorderPickStatus.combined([.complete, .building]), .building)
    }
}
