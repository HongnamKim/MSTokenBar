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
        XCTAssertNil(GunplaID.decode(100_128), "save code 8 belongs to no grade")
        XCTAssertTrue(GunplaID.isGunpla(id))
        XCTAssertFalse(GunplaID.isGunpla(25))
    }

    func test_gradeBodyType() {
        XCTAssertEqual(GunplaGrade.mgsd.bodyType, .sd)
        XCTAssertEqual(GunplaGrade.hg.bodyType, .real)
        XCTAssertEqual(GunplaGrade.verka.bodyType, .real)
        XCTAssertEqual(GunplaGrade.mgex.bodyType, .real)
    }

    func test_growthOrderPlacesVerKaAndMGEXBetweenMGAndPG() {
        XCTAssertEqual(GunplaGrade.allCases.map(\.label), ["SD", "MGSD", "HG", "RG", "MG", "Ver.Ka", "MGEX", "PG"])
        XCTAssertEqual(GunplaGrade.allCases.map(\.growthRank), Array(0...7))
        XCTAssertEqual(GunplaGrade.allCases.shuffled().sorted(), GunplaGrade.allCases)
        XCTAssertTrue(GunplaGrade.mg < .verka && GunplaGrade.verka < .mgex && GunplaGrade.mgex < .pg)
        XCTAssertEqual(Set<GunplaGrade>([.mg, .verka, .pg]).max(), .pg)
    }

    /// Species ids are persisted, so a grade's save code can never move. Ver.Ka and MGEX sit between MG and
    /// PG in growth order but take the next free codes; every number here is a literal on purpose.
    func test_saveCodesAreFixedAndIndependentOfGrowthOrder() {
        let codes: [(GunplaGrade, Int)] = [(.sd, 0), (.mgsd, 1), (.hg, 2), (.rg, 3), (.mg, 4), (.pg, 5),
                                           (.verka, 6), (.mgex, 7)]
        XCTAssertEqual(Set(codes.map(\.0)), Set(GunplaGrade.allCases), "a new grade needs a code here")
        for (grade, code) in codes {
            XCTAssertEqual(grade.saveCode, code, grade.label)
            XCTAssertEqual(GunplaID.encode(machineID: 12, grade: grade), 100_120 + code, grade.label)
            XCTAssertEqual(GunplaID.decode(100_120 + code)?.grade, grade, grade.label)
            XCTAssertEqual(GunplaID.decode(100_120 + code)?.machineID, 12, grade.label)
        }
        XCTAssertLessThan(codes.map(\.1).max() ?? 10, 10, "the id leaves one decimal digit for the grade")
    }

    /// A save written by 0.1.x–0.3.0 holds these ids; they must keep meaning the same grades.
    func test_speciesIDsWrittenBeforeVerKaStillDecodeToTheSameGrades() {
        let saved: [(Int, GunplaGrade)] = [(100_010, .sd), (100_011, .mgsd), (100_012, .hg), (100_013, .rg),
                                           (100_014, .mg), (100_015, .pg)]
        for (id, grade) in saved {
            XCTAssertEqual(GunplaID.decode(id)?.grade, grade, "\(id)")
            XCTAssertEqual(GunplaID.decode(id)?.machineID, 1, "\(id)")
        }
    }

    func test_orderKeyFollowsGrowthOrderNotSaveCode() {
        let key = { GunplaID.orderKey(GunplaID.encode(machineID: $0, grade: $1)) }
        XCTAssertLessThan(key(1, .mg), key(1, .verka))
        XCTAssertLessThan(key(1, .verka), key(1, .mgex))
        XCTAssertLessThan(key(1, .mgex), key(1, .pg))
        XCTAssertLessThan(key(1, .pg), key(2, .sd), "machines still sort before grades")
        XCTAssertEqual(GunplaID.orderKey(25), 25, "ids that are not machines keep their own order")
    }

    func test_bundledCatalogLoadsAndIsValid() throws {
        let c = try MachineCatalog.bundled()
        XCTAssertEqual(c.machines.count, 243)
        XCTAssertFalse(c.machines.filter { $0.variantOf != nil }.isEmpty)
        XCTAssertEqual(c.machine(id: 3)?.isVariant, true)
        XCTAssertEqual(c.machine(speciesID: GunplaID.encode(machineID: 1, grade: .pg))?.id, 1)
        XCTAssertNil(c.machine(speciesID: 25))
        XCTAssertEqual(c.series.count, 25)
    }

    func test_fullArmorUnicornModesFollowTheReleasedFrameColors() throws {
        let catalog = MachineCatalog.shared
        let unicorn = try XCTUnwrap(catalog.machine(id: 116))
        let destroy = try XCTUnwrap(catalog.machine(id: 117))
        let awakened = try XCTUnwrap(catalog.machine(id: 118))
        XCTAssertEqual([unicorn.hangarID, destroy.hangarID, awakened.hangarID], [116, 116, 116])
        XCTAssertEqual(unicorn.grades, [.sd, .hg, .rg, .mg, .verka])
        XCTAssertEqual(destroy.grades, [.hg, .mg])
        XCTAssertEqual(awakened.grades, [.sd, .hg, .rg, .verka])
        XCTAssertEqual(destroy.sprites?["hg"], "full-armor-unicorn-destroy-hg")
        XCTAssertEqual(awakened.sprites?["hg"], "full-armor-unicorn-awakened-hg")
        XCTAssertNotEqual(destroy.gradeSources?["hg"], awakened.gradeSources?["hg"])
    }

    func test_narrativeEquipmentAndPhenexModesKeepTheirReleasedGrades() throws {
        let catalog = try MachineCatalog.bundled()
        let tracks: [(Int, Int, [GunplaGrade])] = [
            (119, 119, [.hg, .verka]), (120, 119, [.hg]), (121, 119, [.hg, .verka]),
            (122, 122, [.hg, .rg, .mg, .pg]), (123, 122, [.sd, .hg, .rg, .mg, .pg]),
        ]
        for (id, hangarID, grades) in tracks {
            let machine = try XCTUnwrap(catalog.machine(id: id))
            XCTAssertEqual(machine.hangarID, hangarID)
            XCTAssertEqual(machine.grades, grades)
        }
    }

    func test_wingZeroDesignsWithTheSameModelNumberHaveSeparateHangarSlots() throws {
        let catalog = try MachineCatalog.bundled()
        let tv = try XCTUnwrap(catalog.machine(id: 145))
        let ew = try XCTUnwrap(catalog.machine(id: 148))
        XCTAssertEqual(tv.modelNumber, ew.modelNumber)
        XCTAssertNotEqual(tv.hangarID, ew.hangarID)
        XCTAssertEqual(tv.grades, [.sd, .hg, .rg, .mg])
        XCTAssertEqual(ew.grades, [.sd, .mgsd, .hg, .rg, .mg, .verka, .pg])
        let tvSprites = Set((tv.sprites ?? [:]).values)
        XCTAssertTrue(tvSprites.isDisjoint(with: (ew.sprites ?? [:]).values))
    }

    func test_strikePacksShareOneEntryAndKeepTheirOwnReleasedGrades() throws {
        let catalog = try MachineCatalog.bundled()
        let loadouts: [(Int, [GunplaGrade])] = [
            (156, [.sd, .hg, .rg, .mg, .pg]), (157, [.sd, .hg, .rg, .mg]),
            (158, [.sd, .rg, .mg]), (159, [.sd, .rg, .mg]),
        ]
        var spriteNames = Set<String>()
        for (id, grades) in loadouts {
            let machine = try XCTUnwrap(catalog.machine(id: id))
            XCTAssertEqual(machine.hangarID, 156)
            XCTAssertEqual(machine.grades, grades)
            let sprites = try XCTUnwrap(machine.sprites)
            XCTAssertTrue(spriteNames.isDisjoint(with: sprites.values))
            spriteNames.formUnion(sprites.values)
        }
        XCTAssertEqual(spriteNames.count, 15)
    }

    func test_impulseSilhouettesShareOneEntryAndHaveSeparateGradeArt() throws {
        let catalog = try MachineCatalog.bundled()
        let loadouts: [(Int, [GunplaGrade])] = [
            (164, [.sd, .hg, .rg, .mg]), (165, [.sd, .hg, .rg, .mg]),
            (166, [.hg, .rg, .mg]), (167, [.hg, .mg]),
        ]
        var art = Set<String>()
        for (id, grades) in loadouts {
            let machine = try XCTUnwrap(catalog.machine(id: id))
            XCTAssertEqual(machine.hangarID, 164)
            XCTAssertEqual(machine.grades, grades)
            let sprites = try XCTUnwrap(machine.sprites)
            XCTAssertTrue(art.isDisjoint(with: sprites.values))
            art.formUnion(sprites.values)
        }
        XCTAssertEqual(art.count, 13)
    }

    func test_00RaiserSharesThe00GundamHangarSlot() throws {
        let catalog = try MachineCatalog.bundled()
        let base = try XCTUnwrap(catalog.machine(id: 174))
        let raiser = try XCTUnwrap(catalog.machine(id: 176))
        XCTAssertEqual(base.hangarID, raiser.hangarID)
        XCTAssertEqual(base.grades, [.sd, .hg])
        XCTAssertEqual(raiser.grades, [.sd, .hg, .rg, .mg, .pg])
        let baseSprites = try XCTUnwrap(base.sprites)
        let raiserSprites = try XCTUnwrap(raiser.sprites)
        XCTAssertTrue(Set(baseSprites.values).isDisjoint(with: raiserSprites.values))
    }

    func test_akatsukiEquipmentSharesOneHangarSlot() throws {
        let catalog = try MachineCatalog.bundled()
        let oowashi = try XCTUnwrap(catalog.machine(id: 215))
        let shiranui = try XCTUnwrap(catalog.machine(id: 216))
        XCTAssertEqual(oowashi.hangarID, shiranui.hangarID)
        XCTAssertEqual(oowashi.grades, [.hg, .rg])
        XCTAssertEqual(shiranui.grades, [.hg])
        XCTAssertNotEqual(oowashi.sprites?["hg"], shiranui.sprites?["hg"])
    }

    func test_completedSeriesServeGradeSpecificArtAndKitSources() throws {
        let catalog = try MachineCatalog.bundled()
        let bandaiHosts: Set<String> = ["manual.bandai-hobby.net", "bandai-hobby.net",
                                        "www.bandaispirits.co.jp", "www.bandainamco.co.jp", "p-bandai.jp"]
        let counts = ["first": 16, "08th-ms-team": 6, "0080": 10, "0083": 12,
                      "the-origin": 7, "thunderbolt": 6, "cucuruz-doans-island": 7,
                      "zeta": 13, "zz": 10, "cca": 8, "beltorchika-children": 2, "uc": 14,
                      "narrative": 5, "hathaway": 6, "f91": 4, "victory": 4,
                      "g-gundam": 9, "gundam-wing": 15, "endless-waltz": 6, "after-war-x": 7, "turn-a-gundam": 2,
                      "gundam-seed": 14, "gundam-seed-destiny": 15, "gundam-00": 23, "gundam-00-movie": 5]
        // These vintage kits are documented by their original Bandai instruction booklets.
        let printedManuals = [
            "gundam-f91-sd": "https://www.dalong.net/reviews/sd/g21/p/g21_m0001.jpg",
            "wing-gundam-tv-sd": "https://www.dalong.net/reviews/sd/g34/p/g34_m0001.JPG",
            "victory-gundam-sd": "https://www.dalong.net/reviews/sd/g23/p/g23_m0001.JPG",
        ]
        for (series, count) in counts {
            let machines = catalog.machines.filter { $0.series == series }
            XCTAssertEqual(Set(machines.map(\.hangarID)).count, count, series)
            for machine in machines {
                let grades = Set(machine.grades.map(\.rawValue))
                let sources = machine.gradeSources ?? [:]
                let sprites = machine.sprites ?? [:]
                XCTAssertEqual(Set(sources.keys), grades, machine.modelNumber)
                XCTAssertEqual(Set(sprites.keys), grades, machine.modelNumber)
                XCTAssertEqual(Set(sprites.values).count, grades.count, machine.modelNumber)
                XCTAssertNotNil(MachineCatalog.shared.machine(id: machine.id), machine.modelNumber)
                for (grade, url) in sources {
                    if let manual = printedManuals[sprites[grade] ?? ""] {
                        XCTAssertEqual(url, manual)
                        continue
                    }
                    XCTAssertTrue(bandaiHosts.contains(URL(string: url)?.host ?? ""), url)
                }
            }
        }
    }

    func test_rejectsInvalidRecords() {
        assertRejects([m(1), m(1)], .duplicateID(1))
        assertRejects([m(1, grades: [])], .emptyGrades(1))
        assertRejects([m(1, grades: [.mg, .hg])], .unsortedGrades(1))
        assertRejects([m(1, grades: [.mg, .pg, .verka])], .unsortedGrades(1))   // save-code order is not growth order
        assertRejects([m(1, grades: [.mgex, .verka])], .unsortedGrades(1))
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
        XCTAssertNoThrow(try MachineCatalog(machines: [m(1, grades: [.hg, .mg, .verka, .mgex, .pg])], series: [s]))
        XCTAssertNoThrow(try MachineCatalog(machines: [m(1, grades: [.hg, .verka])], series: [s]), "Ver.Ka without an MG")
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
        for machine in artless { XCTAssertNil(shared.machine(id: machine.id), machine.modelNumber) }
    }
}
