import XCTest
@testable import PokeTokenBar

final class MachineProfileTests: XCTestCase {
    func test_profileForSpecies() {
        let profile = MachineCatalog.allBundled.profile(speciesID: GunplaID.encode(machineID: 2, grade: .hg))
        XCTAssertEqual(profile?.modelNumber, "MS-06F")
        XCTAssertEqual(profile?.releasedGrades, [.sd, .hg, .rg, .mg, .pg])
        XCTAssertEqual(profile?.factionKey, MachineCatalog.allBundled.machine(id: 2)?.faction)
        XCTAssertEqual(profile?.seriesID, MachineCatalog.allBundled.machine(id: 2)?.series)
    }

    func test_unknownSpeciesHasNoProfile() {
        XCTAssertNil(MachineCatalog.allBundled.profile(speciesID: 25))
        XCTAssertNil(MachineCatalog.allBundled.profile(speciesID: GunplaID.encode(machineID: 9_999, grade: .hg)))
    }

    func test_factionNames() {
        XCTAssertEqual(L(.ko).factionName("zeon"), "지온공국군")
        XCTAssertEqual(L(.en).factionName("neo_zeon"), "Neo Zeon")
        XCTAssertEqual(L(.ja).factionName("londo_bell"), "ロンド・ベル")
        XCTAssertEqual(L(.en).factionName("mystery"), "mystery")
    }
}
