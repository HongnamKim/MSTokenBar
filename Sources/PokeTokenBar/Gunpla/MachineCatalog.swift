import Foundation

struct MachineRecord: Codable, Sendable {
    let id: Int
    let modelNumber: String
    let names: [String: String]
    let series: String
    let faction: String
    let rarity: Rarity
    let grades: [GunplaGrade]
    let gradeSources: [String: String]?
    let variantOf: Int?
    /// Keys: grade rawValues for per-grade art, plus "sdBody" / "realBody" for body-type art shared across grades.
    let sprites: [String: String]?

    /// Modes earn their own grades but share one physical suit in the hangar.
    var hangarGroupID: Int? = nil
    var hangarID: Int { hangarGroupID ?? id }
    var isVariant: Bool { variantOf != nil }
}

struct SeriesRecord: Codable, Sendable {
    let id: String
    let names: [String: String]
    let order: Int
}

enum CatalogError: Error, Equatable {
    case duplicateID(Int)
    case emptyGrades(Int)
    case unsortedGrades(Int)
    case unknownSeries(Int, String)
    case unknownVariantBase(Int, Int)
    case variantOfVariant(Int)
    case invalidHangarGroup(Int)
    case idOutOfRange(Int)
    case missingName(Int, String)
}

struct MachineCatalog: Sendable {
    let machines: [MachineRecord]
    let series: [SeriesRecord]
    private let byID: [Int: MachineRecord]

    init(machines: [MachineRecord], series: [SeriesRecord]) throws {
        let seriesIDs = Set(series.map(\.id))
        var byID: [Int: MachineRecord] = [:]
        for m in machines {
            guard (1...9_999).contains(m.id) else { throw CatalogError.idOutOfRange(m.id) }
            guard byID[m.id] == nil else { throw CatalogError.duplicateID(m.id) }
            byID[m.id] = m
        }
        for m in machines {
            guard !m.grades.isEmpty else { throw CatalogError.emptyGrades(m.id) }
            guard m.grades == m.grades.sorted(), Set(m.grades).count == m.grades.count else {
                throw CatalogError.unsortedGrades(m.id)
            }
            guard seriesIDs.contains(m.series) else { throw CatalogError.unknownSeries(m.id, m.series) }
            for lang in ["ko", "en", "ja"] where (m.names[lang] ?? "").isEmpty {
                throw CatalogError.missingName(m.id, lang)
            }
            if let id = m.hangarGroupID {
                guard let parent = byID[id], parent.hangarGroupID == nil, parent.id != m.id,
                      parent.series == m.series, parent.variantOf == m.variantOf else {
                    throw CatalogError.invalidHangarGroup(m.id)
                }
            }
            if let base = m.variantOf {
                guard let baseRecord = byID[base] else { throw CatalogError.unknownVariantBase(m.id, base) }
                guard baseRecord.variantOf == nil else { throw CatalogError.variantOfVariant(m.id) }
            }
        }
        self.machines = machines
        self.series = series
        self.byID = byID
    }

    func machine(id: Int) -> MachineRecord? { byID[id] }

    func machine(speciesID: Int) -> MachineRecord? {
        GunplaID.decode(speciesID).flatMap { byID[$0.machineID] }
    }

    static func bundled(bundle: Bundle = GunplaResources.bundle) throws -> MachineCatalog {
        struct MachinesFile: Decodable { let machines: [MachineRecord] }
        struct SeriesFile: Decodable { let series: [SeriesRecord] }
        let decoder = JSONDecoder()
        func data(_ name: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Gunpla") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try Data(contentsOf: url)
        }
        return try MachineCatalog(
            machines: decoder.decode(MachinesFile.self, from: data("machines")).machines,
            series: decoder.decode(SeriesFile.self, from: data("series")).series
        )
    }

    /// Only machines with bundled art for every released grade can appear (the silhouette is a fallback,
    /// not art). A variant leaves with its base, and a series with no machine left is hidden.
    func keepingMachinesWithArt(bundle: Bundle = GunplaResources.bundle) throws -> MachineCatalog {
        let ready = Set(machines.filter { machine in
            machine.grades.allSatisfy { BundledSprites.artName(sprites: machine.sprites, grade: $0, bundle: bundle) != nil }
        }.map(\.id))
        let kept = machines.filter { machine in
            ready.contains(machine.id) && ready.contains(machine.hangarID) && (machine.variantOf.map(ready.contains) ?? true)
        }
        let keptSeries = Set(kept.map(\.series))
        return try MachineCatalog(machines: kept, series: series.filter { keptSeries.contains($0.id) })
    }

    // The bundled data is guaranteed valid by MachineCatalogTests.
    static let shared: MachineCatalog = try! bundled().keepingMachinesWithArt()
}
