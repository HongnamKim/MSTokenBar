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
        XCTAssertEqual(c.machines.count, 22)
        XCTAssertFalse(c.machines.filter { $0.variantOf != nil }.isEmpty)
        XCTAssertEqual(c.machine(id: 3)?.isVariant, true)
        XCTAssertEqual(c.machine(speciesID: GunplaID.encode(machineID: 1, grade: .pg))?.id, 1)
        XCTAssertNil(c.machine(speciesID: 25))
        XCTAssertEqual(c.series.count, 4)
    }

    /// Verified series list only released kits: every grade cites an official Bandai page, and nothing
    /// outside the confirmed roster (docs/gunpla/initial-roster.md) is left in the series.
    func test_firstSeriesCitesABandaiSourceForEveryGrade() throws {
        let first = try MachineCatalog.bundled().machines.filter { $0.series == "first" }
        XCTAssertEqual(first.count, 16, "the confirmed Mobile Suit Gundam roster")
        let bandaiHosts: Set<String> = ["manual.bandai-hobby.net", "bandai-hobby.net",
                                        "www.bandaispirits.co.jp", "p-bandai.jp"]
        for machine in first {
            let sources = machine.gradeSources ?? [:]
            XCTAssertEqual(Set(sources.keys), Set(machine.grades.map(\.rawValue)), machine.modelNumber)
            for (grade, url) in sources {
                let host = URL(string: url)?.host ?? ""
                XCTAssertTrue(bandaiHosts.contains(host), "\(machine.modelNumber) \(grade): \(url)")
            }
        }
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
        XCTAssertEqual(c.machine(id: 2)?.variantOf, 1)
        XCTAssertNil(c.machine(id: 5))
    }

    // MARK: only machines with art appear

    private func art(_ id: Int, grades: [GunplaGrade], series: String = "first", variantOf: Int? = nil,
                     sprites: [String: String]?) -> MachineRecord {
        MachineRecord(id: id, modelNumber: "X-\(id)", names: ["ko": "가", "en": "A", "ja": "あ"], series: series,
                      faction: "efsf", rarity: .common, grades: grades, gradeSources: nil,
                      variantOf: variantOf, sprites: sprites)
    }

    func test_keepsOnlyMachinesWithArtForEveryGrade() throws {
        let series = [SeriesRecord(id: "first", names: [:], order: 0), SeriesRecord(id: "zeta", names: [:], order: 1)]
        let catalog = try MachineCatalog(machines: [
            art(1, grades: [.hg, .mg], sprites: ["hg": "zaku-ii-hg", "mg": "zaku-ii-mg"]),     // every grade drawn
            art(2, grades: [.hg, .mg], sprites: ["hg": "zaku-ii-hg"]),                          // MG missing
            art(3, grades: [.hg], variantOf: 2, sprites: ["hg": "zaku-ii-hg"]),                 // base missing art
            art(4, grades: [.hg, .mg], sprites: ["realBody": "zaku-ii-hg"]),                    // body-type art counts
            art(5, grades: [.hg], sprites: ["hg": "no-such-sprite"]),                           // file not bundled
            art(6, grades: [.hg], series: "zeta", sprites: nil),                                // series left empty
        ], series: series).keepingMachinesWithArt()

        XCTAssertEqual(catalog.machines.map(\.id), [1, 4])
        XCTAssertNil(catalog.machine(id: 3), "a variant leaves with its base")
        XCTAssertEqual(catalog.series.map(\.id), ["first"], "a series with no machine left is hidden")
    }

    func test_sharedCatalogOnlyServesMachinesWithArt() throws {
        let shared = MachineCatalog.shared
        XCTAssertFalse(shared.machines.isEmpty)
        for machine in shared.machines {
            for grade in machine.grades {
                XCTAssertNotNil(BundledSprites.artName(sprites: machine.sprites, grade: grade),
                                "\(machine.modelNumber) \(grade.label) would show a silhouette")
            }
        }
        let bundled = try MachineCatalog.bundled()
        let artless = bundled.machines.filter { $0.sprites == nil }
        XCTAssertFalse(artless.isEmpty, "the bundled data still lists machines without art")
        for machine in artless { XCTAssertNil(shared.machine(id: machine.id), machine.modelNumber) }
    }
}
