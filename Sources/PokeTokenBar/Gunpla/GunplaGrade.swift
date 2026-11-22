import Foundation

enum BodyType: String, Sendable { case sd, real }

enum GunplaGrade: String, Codable, CaseIterable, Comparable, Sendable {
    case sd, mgsd, hg, rg, mg, pg

    var index: Int { Self.allCases.firstIndex(of: self)! }

    var label: String {
        switch self {
        case .sd: return "SD"
        case .mgsd: return "MGSD"
        case .hg: return "HG"
        case .rg: return "RG"
        case .mg: return "MG"
        case .pg: return "PG"
        }
    }

    var bodyType: BodyType {
        switch self {
        case .sd, .mgsd: return .sd
        case .hg, .rg, .mg, .pg: return .real
        }
    }

    static func < (lhs: GunplaGrade, rhs: GunplaGrade) -> Bool { lhs.index < rhs.index }
}

/// Synthetic species ids: `100_000 + machineID * 10 + gradeIndex`, kept clear of the Pokémon range.
enum GunplaID {
    static let base = 100_000

    static func encode(machineID: Int, grade: GunplaGrade) -> Int {
        base + machineID * 10 + grade.index
    }

    static func decode(_ speciesID: Int) -> (machineID: Int, grade: GunplaGrade)? {
        guard speciesID >= base else { return nil }
        let offset = speciesID - base
        let machineID = offset / 10
        guard (1...9_999).contains(machineID),
              let grade = GunplaGrade.allCases[safe: offset % 10] else { return nil }
        return (machineID, grade)
    }

    static func isGunpla(_ speciesID: Int) -> Bool { decode(speciesID) != nil }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
