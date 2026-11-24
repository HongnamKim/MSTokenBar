import XCTest
@testable import PokeTokenBar

final class CatalogProviderTests: XCTestCase {
    private func pathIDs(_ node: EvoNode) -> [Int] {
        [node.speciesID] + (node.children.first.map(pathIDs) ?? [])
    }

    func test_lineFromFirstGradeCoversAllReleasedGrades() async throws {
        let line = try await MachineCatalog.allBundled.line(baseSpeciesID: GunplaID.encode(machineID: 2, grade: .sd))
        XCTAssertEqual(pathIDs(line.tree), [.sd, .hg, .rg, .mg, .pg].map { GunplaID.encode(machineID: 2, grade: $0) })
        XCTAssertEqual(line.totalForms, 5)
        XCTAssertEqual(line.rarity, .common)
        XCTAssertEqual(line.localizedName(GunplaID.encode(machineID: 2, grade: .hg), .ko), "HG 자쿠 II")
    }

    func test_lineFromResumedGradeStartsThere() async throws {
        let line = try await MachineCatalog.allBundled.line(baseSpeciesID: GunplaID.encode(machineID: 1, grade: .rg))
        XCTAssertEqual(line.totalForms, 4) // rg, mg, verka, pg
    }

    func test_singleGradeMachineHasOneStage() async throws {
        let series = SeriesRecord(id: "first", names: ["ko": "가", "en": "A", "ja": "あ"], order: 0)
        let mgOnly = MachineRecord(
            id: 1, modelNumber: "X-1", names: ["ko": "가", "en": "A", "ja": "あ"], series: "first",
            faction: "zeon", rarity: .rare, grades: [.mg], gradeSources: nil, variantOf: nil, sprites: nil)
        let catalog = try MachineCatalog(machines: [mgOnly], series: [series])
        let line = try await catalog.line(baseSpeciesID: GunplaID.encode(machineID: 1, grade: .mg))
        XCTAssertEqual(line.totalForms, 1)
    }

    private func catalog(grades: [GunplaGrade]) throws -> MachineCatalog {
        let series = SeriesRecord(id: "first", names: ["ko": "가", "en": "A", "ja": "あ"], order: 0)
        let machine = MachineRecord(
            id: 1, modelNumber: "X-1", names: ["ko": "가", "en": "A", "ja": "あ"], series: "first",
            faction: "efsf", rarity: .rare, grades: grades, gradeSources: nil, variantOf: nil, sprites: nil)
        return try MachineCatalog(machines: [machine], series: [series])
    }

    /// PG's save code (5) is lower than Ver.Ka's (6) and MGEX's (7): the line must follow growth order.
    func test_lineRunsMGThenVerKaThenMGEXThenPG() async throws {
        let id = { GunplaID.encode(machineID: 1, grade: $0) }
        let line = try await catalog(grades: [.hg, .mg, .verka, .mgex, .pg]).line(baseSpeciesID: id(.hg))
        XCTAssertEqual(pathIDs(line.tree), [.hg, .mg, .verka, .mgex, .pg].map(id))
        XCTAssertEqual(line.localizedName(id(.verka), .en), "Ver.Ka A")
        XCTAssertEqual(line.localizedName(id(.mgex), .en), "MGEX A")

        let resumed = try await catalog(grades: [.hg, .mg, .verka, .mgex, .pg]).line(baseSpeciesID: id(.verka))
        XCTAssertEqual(pathIDs(resumed.tree), [.verka, .mgex, .pg].map(id))
    }

    /// A machine whose only 1/100 Master Grade kit is a Ver.Ka skips MG.
    func test_verKaOnlyMachineSkipsMG() async throws {
        let id = { GunplaID.encode(machineID: 1, grade: $0) }
        let line = try await catalog(grades: [.hg, .verka]).line(baseSpeciesID: id(.hg))
        XCTAssertEqual(pathIDs(line.tree), [id(.hg), id(.verka)])
    }

    func test_unreleasedGradeThrows() async {
        do {
            _ = try await MachineCatalog.allBundled.line(baseSpeciesID: GunplaID.encode(machineID: 4, grade: .rg))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? CatalogProviderError, .unreleasedGrade(GunplaID.encode(machineID: 4, grade: .rg)))
        }
    }

    func test_unknownSpeciesThrows() async {
        do {
            _ = try await MachineCatalog.allBundled.line(baseSpeciesID: 25)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? CatalogProviderError, .unknownSpecies(25))
        }
    }

    func test_unusedProviderMethodsAreEmpty() async throws {
        let index = try await MachineCatalog.allBundled.baseSpeciesIndex()
        XCTAssertTrue(index.isEmpty)
        let one = try await MachineCatalog.allBundled.baseSpecies(id: 1)
        XCTAssertNil(one)
    }

    func test_englishNameForUnnamedLanguageFallback() async throws {
        let id = GunplaID.encode(machineID: 2, grade: .hg)
        let line = try await MachineCatalog.allBundled.line(baseSpeciesID: id)
        XCTAssertTrue(line.localizedName(id, .en).hasPrefix("HG "))
    }
}
