import CoreGraphics
import Foundation

enum BodyType: String, Sendable { case sd, real }

/// Declared in growth order (spec §5.2): a machine is raised through its released grades in this order.
/// The order may change when a grade line is added — nothing persisted depends on it. See `saveCode`.
enum GunplaGrade: String, Codable, CaseIterable, Comparable, Sendable {
    case sd, mgsd, hg, rg, mg, verka, mgex, pg

    /// Position in the growth order. Never persisted.
    var growthRank: Int { Self.allCases.firstIndex(of: self)! }

    /// The digit species ids persist for this grade. Fixed forever: a new grade takes the next free code
    /// wherever it sits in the growth order, and a code is never renumbered or reused.
    /// Codes 0–5 are the growth order of 0.1.0; Ver.Ka and MGEX were added after it.
    var saveCode: Int {
        switch self {
        case .sd: return 0
        case .mgsd: return 1
        case .hg: return 2
        case .rg: return 3
        case .mg: return 4
        case .pg: return 5
        case .verka: return 6
        case .mgex: return 7
        }
    }

    static let bySaveCode = Dictionary(uniqueKeysWithValues: allCases.map { ($0.saveCode, $0) })

    var label: String {
        switch self {
        case .sd: return "SD"
        case .mgsd: return "MGSD"
        case .hg: return "HG"
        case .rg: return "RG"
        case .mg: return "MG"
        case .verka: return "Ver.Ka"
        case .mgex: return "MGEX"
        case .pg: return "PG"
        }
    }

    var bodyType: BodyType {
        switch self {
        case .sd, .mgsd: return .sd
        case .hg, .rg, .mg, .verka, .mgex, .pg: return .real
        }
    }

    /// Same body type: the higher the grade, the bigger it is drawn.
    var displayScale: CGFloat {
        switch self {
        case .sd: return 0.85
        case .mgsd: return 1.0
        case .hg: return 0.8
        case .rg: return 0.88
        case .mg: return 0.95
        case .verka: return 0.98
        case .mgex: return 1.01
        case .pg: return 1.05
        }
    }

    static func < (lhs: GunplaGrade, rhs: GunplaGrade) -> Bool { lhs.growthRank < rhs.growthRank }
}

/// Synthetic species ids: `100_000 + machineID * 10 + grade.saveCode`, kept clear of the Pokémon range.
/// An id is an identity, not a rank: the ids of one machine are not in growth order, so compare grades
/// (or `orderKey`), never raw ids.
enum GunplaID {
    static let base = 100_000

    static func encode(machineID: Int, grade: GunplaGrade) -> Int {
        base + machineID * 10 + grade.saveCode
    }

    static func decode(_ speciesID: Int) -> (machineID: Int, grade: GunplaGrade)? {
        guard speciesID >= base else { return nil }
        let offset = speciesID - base
        let machineID = offset / 10
        guard (1...9_999).contains(machineID),
              let grade = GunplaGrade.bySaveCode[offset % 10] else { return nil }
        return (machineID, grade)
    }

    static func isGunpla(_ speciesID: Int) -> Bool { decode(speciesID) != nil }

    /// Sort key that lists machines by id and each machine's grades in growth order.
    /// Ids that are not machines keep their own value.
    static func orderKey(_ speciesID: Int) -> Int {
        decode(speciesID).map { base + $0.machineID * 10 + $0.grade.growthRank } ?? speciesID
    }
}
