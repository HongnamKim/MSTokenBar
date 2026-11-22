import Foundation

enum CatalogProviderError: Error, Equatable {
    case unknownSpecies(Int)
    case unreleasedGrade(Int)
}

/// Serves each machine's released grades as a linear `EvoLine` (one node per grade).
extension MachineCatalog: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        guard let decoded = GunplaID.decode(baseSpeciesID),
              let machine = machine(id: decoded.machineID) else {
            throw CatalogProviderError.unknownSpecies(baseSpeciesID)
        }
        guard machine.grades.contains(decoded.grade) else {
            throw CatalogProviderError.unreleasedGrade(baseSpeciesID)
        }
        let remaining = machine.grades.filter { $0 >= decoded.grade }
        var names: [Int: [String: String]] = [:]
        var tree: EvoNode?
        for grade in remaining.reversed() {
            let id = GunplaID.encode(machineID: machine.id, grade: grade)
            names[id] = machine.names.mapValues { "\(grade.label) \($0)" }
            tree = EvoNode(speciesID: id, children: tree.map { [$0] } ?? [])
        }
        return EvoLine(baseID: baseSpeciesID, tree: tree!, rarity: machine.rarity, names: names)
    }

    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }

    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}
