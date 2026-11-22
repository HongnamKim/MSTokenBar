import XCTest
@testable import PokeTokenBar

final class CatalogProviderTests: XCTestCase {
    private func pathIDs(_ node: EvoNode) -> [Int] {
        [node.speciesID] + (node.children.first.map(pathIDs) ?? [])
    }

    func test_lineFromFirstGradeCoversAllReleasedGrades() async throws {
        let line = try await MachineCatalog.shared.line(baseSpeciesID: GunplaID.encode(machineID: 2, grade: .sd))
        XCTAssertEqual(pathIDs(line.tree), [.sd, .hg, .rg, .mg, .pg].map { GunplaID.encode(machineID: 2, grade: $0) })
        XCTAssertEqual(line.totalForms, 5)
        XCTAssertEqual(line.rarity, .common)
        XCTAssertEqual(line.localizedName(GunplaID.encode(machineID: 2, grade: .hg), .ko), "HG 자쿠 II")
    }

    func test_lineFromResumedGradeStartsThere() async throws {
        let line = try await MachineCatalog.shared.line(baseSpeciesID: GunplaID.encode(machineID: 1, grade: .rg))
        XCTAssertEqual(line.totalForms, 3) // rg, mg, pg
    }

    func test_singleGradeMachineHasOneStage() async throws {
        let line = try await MachineCatalog.shared.line(baseSpeciesID: GunplaID.encode(machineID: 12, grade: .mg))
        XCTAssertEqual(line.totalForms, 1)
    }

    func test_unreleasedGradeThrows() async {
        do {
            _ = try await MachineCatalog.shared.line(baseSpeciesID: GunplaID.encode(machineID: 4, grade: .rg))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? CatalogProviderError, .unreleasedGrade(GunplaID.encode(machineID: 4, grade: .rg)))
        }
    }

    func test_unknownSpeciesThrows() async {
        do {
            _ = try await MachineCatalog.shared.line(baseSpeciesID: 25)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? CatalogProviderError, .unknownSpecies(25))
        }
    }

    func test_unusedProviderMethodsAreEmpty() async throws {
        let index = try await MachineCatalog.shared.baseSpeciesIndex()
        XCTAssertTrue(index.isEmpty)
        let one = try await MachineCatalog.shared.baseSpecies(id: 1)
        XCTAssertNil(one)
    }

    func test_englishNameForUnnamedLanguageFallback() async throws {
        let id = GunplaID.encode(machineID: 2, grade: .hg)
        let line = try await MachineCatalog.shared.line(baseSpeciesID: id)
        XCTAssertTrue(line.localizedName(id, .en).hasPrefix("HG "))
    }
}
