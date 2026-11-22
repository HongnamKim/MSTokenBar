import Foundation

/// What the detail page shows about a machine: identity facts from the catalog, never per-individual state.
struct MachineProfile: Equatable, Sendable {
    let modelNumber: String
    let factionKey: String
    let seriesID: String
    let releasedGrades: [GunplaGrade]
}

extension MachineCatalog {
    func profile(speciesID: Int) -> MachineProfile? {
        machine(speciesID: speciesID).map {
            MachineProfile(modelNumber: $0.modelNumber, factionKey: $0.faction,
                           seriesID: $0.series, releasedGrades: $0.grades)
        }
    }
}
