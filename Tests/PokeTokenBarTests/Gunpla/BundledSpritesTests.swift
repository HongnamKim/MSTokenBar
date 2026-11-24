import CoreGraphics
import ImageIO
import XCTest
@testable import PokeTokenBar

private final class CountingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

final class BundledSpritesTests: XCTestCase {
    private let series = SeriesRecord(id: "first", names: ["ko": "퍼스트", "en": "First", "ja": "ファースト"], order: 0)

    private func catalog(grades: [GunplaGrade], sprites: [String: String]?) throws -> MachineCatalog {
        let machine = MachineRecord(
            id: 7, modelNumber: "X-7", names: ["ko": "가", "en": "A", "ja": "あ"], series: "first",
            faction: "efsf", rarity: .common, grades: grades, gradeSources: nil, variantOf: nil, sprites: sprites
        )
        return try MachineCatalog(machines: [machine], series: [series])
    }

    @MainActor
    func testVerKaKitsShareMasterGradeOwnershipWithDistinctBundledArt() throws {
        let catalog = MachineCatalog.shared
        let machines = catalog.machines.filter { $0.alternateKits?.isEmpty == false }
        XCTAssertEqual(Set(machines.map(\.modelNumber)), ["RX-78-2", "MSZ-006", "MSZ-010", "RX-93", "MSN-04", "RX-93-ν2"])

        for machine in machines {
            let model = machine.modelNumber
            XCTAssertEqual(machine.grades.filter { $0 == .mg }.count, 1, model)
            let editions = try XCTUnwrap(machine.alternateKits, model)
            XCTAssertEqual(editions.map(\.label), ["MG Ver.Ka"], model)
            let verKa = try XCTUnwrap(editions.first, model)
            let regularSource = try XCTUnwrap(machine.gradeSources?["mg"], model)
            XCTAssertNotEqual(verKa.source, regularSource, model)

            let id = GunplaID.encode(machineID: machine.id, grade: .mg)
            XCTAssertEqual(BundledSprites.resourceName(speciesID: id, catalog: catalog), machine.sprites?["mg"], model)
            let regular = try XCTUnwrap(BundledSprites.gifData(speciesID: id, catalog: catalog), model)
            let url = try XCTUnwrap(BundledSprites.gifURL(for: verKa), model)
            XCTAssertNotEqual(try Data(contentsOf: url), regular, model)
            XCTAssertNotNil(SpriteLoader.kitPreview(verKa), model)
        }
    }

    func test_firstSeriesGradeArtLoadsForStaticAndAnimatedViews() throws {
        let expected = [
            "RX-78-2": "rx-78-2", "RX-77-2": "guncannon", "RX-75": "guntank", "RGM-79": "gm",
            "MS-05B": "zaku-i", "MS-06F": "zaku-ii", "MS-06S": "chars-zaku-ii", "MS-07B": "gouf",
            "MS-09": "dom", "MS-14A": "gelgoog", "MS-14S": "chars-gelgoog", "MSM-07": "zgok",
            "MSM-07S": "chars-zgok", "MSM-04": "acguy", "YMS-15": "gyan", "MSN-02": "zeong",
        ]
        let first = MachineCatalog.allBundled.machines.filter { $0.series == "first" }
        for (model, art) in expected {
            let machine = try XCTUnwrap(first.first { $0.modelNumber == model }, model)
            XCTAssertTrue(machine.grades.contains(.hg), model)
            for grade in machine.grades {
                XCTAssertNotNil(machine.gradeSources?[grade.rawValue], model)
                let id = GunplaID.encode(machineID: machine.id, grade: grade)
                XCTAssertEqual(BundledSprites.resourceName(speciesID: id), "\(art)-\(grade.rawValue)", model)
                for animated in [false, true] {
                    let data = try XCTUnwrap(SpriteStore.bundledGunplaData(speciesID: id, animated: animated), model)
                    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil), model)
                    XCTAssertEqual(CGImageSourceGetCount(source), animated ? 2 : 1, model)
                    let frame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), model)
                    XCTAssertEqual(frame.width, 128, model)
                    XCTAssertEqual(frame.height, 128, model)
                }
            }
        }
    }

    func test_missingSpriteFallsBackToSilhouette() throws {
        let c = try catalog(grades: [.hg], sprites: ["hg": "does-not-exist"])
        XCTAssertEqual(BundledSprites.resourceName(speciesID: GunplaID.encode(machineID: 7, grade: .hg), catalog: c),
                       "silhouette-real")
        let none = try catalog(grades: [.hg], sprites: nil)
        XCTAssertEqual(BundledSprites.resourceName(speciesID: GunplaID.encode(machineID: 7, grade: .hg), catalog: none),
                       "silhouette-real")
    }

    func test_sdGradesUseSdSilhouette() throws {
        let c = try catalog(grades: [.sd, .mgsd], sprites: nil)
        XCTAssertEqual(BundledSprites.resourceName(speciesID: GunplaID.encode(machineID: 7, grade: .mgsd), catalog: c),
                       "silhouette-sd")
        XCTAssertEqual(BundledSprites.resourceName(speciesID: GunplaID.encode(machineID: 7, grade: .sd), catalog: c),
                       "silhouette-sd")
    }

    func test_bodyTypeKeyIsUsedBeforeSilhouette() throws {
        let c = try catalog(grades: [.mgsd, .hg], sprites: ["realBody": "rx-78-2-hg", "sdBody": "rx-78-2-sd"])
        XCTAssertEqual(BundledSprites.resourceName(speciesID: GunplaID.encode(machineID: 7, grade: .hg), catalog: c),
                       "rx-78-2-hg")
        XCTAssertEqual(BundledSprites.resourceName(speciesID: GunplaID.encode(machineID: 7, grade: .mgsd), catalog: c),
                       "rx-78-2-sd")
    }

    func test_unknownMachineOrPokemonIdHasNoResource() {
        XCTAssertNil(BundledSprites.resourceName(speciesID: 25, catalog: .shared))
        XCTAssertNil(BundledSprites.gifData(speciesID: 25))
    }

    func test_gifDataIsAnimated() throws {
        let ids = [GunplaID.encode(machineID: 1, grade: .hg), GunplaID.encode(machineID: 2, grade: .mgsd),
                   GunplaID.encode(machineID: 2, grade: .hg)]
        for id in ids {
            let data = try XCTUnwrap(BundledSprites.gifData(speciesID: id), "gif for \(id)")
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertGreaterThanOrEqual(CGImageSourceGetCount(source), 2, "frames for \(id)")
        }
    }

    func test_boxPNGIsAvailable() throws {
        let data = try XCTUnwrap(BundledSprites.boxPNG())
        XCTAssertNotNil(CGImageSourceCreateWithData(data as CFData, nil))
    }

    func test_displayScaleValues() {
        let scales = GunplaGrade.allCases.map { Double($0.displayScale) }
        XCTAssertEqual(scales, [0.85, 1.0, 0.8, 0.88, 0.95, 0.98, 1.01, 1.05])
        // Same body type: the higher the grade, the bigger it is drawn.
        let real = GunplaGrade.allCases.filter { $0.bodyType == .real }.map { Double($0.displayScale) }
        XCTAssertEqual(real, real.sorted())
    }

    func test_backSpriteIsNilForGunpla() async {
        let store = SpriteStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("bundled-sprites-\(UUID().uuidString)"))
        let data = await store.data(speciesID: GunplaID.encode(machineID: 1, grade: .hg), animated: true, back: true)
        XCTAssertNil(data)
    }

    func test_gunplaSpriteNeverHitsNetwork() async throws {
        CountingURLProtocol.requestCount = 0
        URLProtocol.registerClass(CountingURLProtocol.self)
        defer { URLProtocol.unregisterClass(CountingURLProtocol.self) }
        let store = SpriteStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("bundled-sprites-\(UUID().uuidString)"))
        let id = GunplaID.encode(machineID: 1, grade: .hg)
        let gif = await store.data(speciesID: id, animated: true)
        let png = await store.data(speciesID: id, animated: false, shiny: true)
        XCTAssertNotNil(gif)
        let pngData = try XCTUnwrap(png)
        XCTAssertEqual(pngData.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(CountingURLProtocol.requestCount, 0)
    }

    @MainActor
    func test_backAnimationFallsBackToFrontFramesForGunpla() async {
        CountingURLProtocol.requestCount = 0
        URLProtocol.registerClass(CountingURLProtocol.self)
        defer { URLProtocol.unregisterClass(CountingURLProtocol.self) }
        let store = SpriteStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("bundled-sprites-\(UUID().uuidString)"))
        let id = GunplaID.encode(machineID: 1, grade: .hg)
        let frames = await SpriteLoader.animationFrames(speciesID: id, shiny: false, store: store, back: true)
        XCTAssertGreaterThanOrEqual(frames.count, 2)
        XCTAssertEqual(CountingURLProtocol.requestCount, 0)
    }

    /// The first synchronous render must not flash the box glyph: bundled art seeds the caches without any
    /// prior async load (the disk cache never holds Gunpla art).
    @MainActor
    func test_cachedSpritesForGunplaNeedNoPriorAsyncLoad() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("bundled-sprites-\(UUID().uuidString)")
        let id = GunplaID.encode(machineID: 1, grade: .rg)
        XCTAssertNotNil(SpriteLoader.cachedImage(speciesID: id, directory: empty))
        XCTAssertNotNil(SpriteLoader.cachedImage(speciesID: id, animated: true, shiny: true, directory: empty))
        XCTAssertNotNil(SpriteLoader.cachedImage(speciesID: id, directory: empty, back: true), "back falls back to front")
        XCTAssertGreaterThanOrEqual(SpriteLoader.cachedFrames(speciesID: id, shiny: false, directory: empty).count, 2)
        XCTAssertTrue(SpriteLoader.cachedFrames(speciesID: id, shiny: false, directory: empty, back: true).isEmpty,
                      "no back art — callers keep the front fallback")
        XCTAssertNil(SpriteLoader.cachedImage(speciesID: 25, directory: empty), "non-Gunpla ids stay disk-only")
    }
}
