import XCTest
@testable import PokeTokenBar

final class MachineCatalogTests: XCTestCase {
    private let s = SeriesRecord(id: "first", names: ["ko": "퍼스트", "en": "First", "ja": "ファースト"], order: 0)

    private func m(
        _ id: Int,
        grades: [GunplaGrade] = [.hg],
        series: String = "first",
        variantOf: Int? = nil,
        names: [String: String] = ["ko": "가", "en": "A", "ja": "あ"]
    ) -> MachineRecord {
        MachineRecord(
            id: id, modelNumber: "X-\(id)", names: names, series: series, faction: "efsf",
            rarity: .common, grades: grades, gradeSources: nil, variantOf: variantOf, sprites: nil
        )
    }

    private func assertRejects(_ machines: [MachineRecord], _ expected: CatalogError, line: UInt = #line) {
        XCTAssertThrowsError(try MachineCatalog(machines: machines, series: [s]), line: line) {
            XCTAssertEqual($0 as? CatalogError, expected, line: line)
        }
    }

    func test_encodeDecodeRoundTrip() {
        let id = GunplaID.encode(machineID: 12, grade: .hg)
        XCTAssertEqual(id, 100_122)
        XCTAssertEqual(GunplaID.decode(id)?.machineID, 12)
        XCTAssertEqual(GunplaID.decode(id)?.grade, .hg)
        XCTAssertNil(GunplaID.decode(25))
        XCTAssertNil(GunplaID.decode(100_126))
        XCTAssertTrue(GunplaID.isGunpla(id))
        XCTAssertFalse(GunplaID.isGunpla(25))
    }

    func test_gradeBodyType() {
        XCTAssertEqual(GunplaGrade.mgsd.bodyType, .sd)
        XCTAssertEqual(GunplaGrade.hg.bodyType, .real)
        XCTAssertEqual(GunplaGrade.allCases.map(\.label), ["SD", "MGSD", "HG", "RG", "MG", "PG"])
        XCTAssertEqual(GunplaGrade.allCases.map(\.index), [0, 1, 2, 3, 4, 5])
        XCTAssertTrue(GunplaGrade.sd < GunplaGrade.pg)
    }

    func test_bundledCatalogLoadsAndIsValid() throws {
        let c = try MachineCatalog.bundled()
        XCTAssertEqual(c.machines.count, 12)
        XCTAssertFalse(c.machines.filter { $0.variantOf != nil }.isEmpty)
        XCTAssertEqual(c.machine(3)?.isVariant, true)
        XCTAssertEqual(c.machine(speciesID: GunplaID.encode(machineID: 1, grade: .pg))?.id, 1)
        XCTAssertNil(c.machine(speciesID: 25))
        XCTAssertEqual(c.series.count, 4)
    }

    func test_rejectsInvalidRecords() {
        assertRejects([m(1), m(1)], .duplicateID(1))
        assertRejects([m(1, grades: [])], .emptyGrades(1))
        assertRejects([m(1, grades: [.mg, .hg])], .unsortedGrades(1))
        assertRejects([m(1, series: "nope")], .unknownSeries(1, "nope"))
        assertRejects([m(1, variantOf: 99)], .unknownVariantBase(1, 99))
        assertRejects([m(1), m(2, variantOf: 1), m(3, variantOf: 2)], .variantOfVariant(3))
        assertRejects([m(0)], .idOutOfRange(0))
        assertRejects([m(10_000)], .idOutOfRange(10_000))
        assertRejects([m(1, names: ["ko": "가", "en": "A"])], .missingName(1, "ja"))
    }

    func test_acceptsValidRecords() throws {
        let c = try MachineCatalog(machines: [m(1), m(2, variantOf: 1)], series: [s])
        XCTAssertEqual(c.machine(2)?.variantOf, 1)
        XCTAssertNil(c.machine(5))
    }
}
