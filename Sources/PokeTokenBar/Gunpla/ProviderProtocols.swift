import Foundation

/// A hatch candidate: the first species of an evolution line and its rarity signal.
struct BaseSpecies: Sendable, Codable {
    let id: Int
    let captureRate: Int
}

/// Supplies evolution lines to `CompanionStore` (injectable; tests use stubs).
/// The app's only real provider is the bundled `MachineCatalog`.
protocol PokeProviding: Sendable {
    func line(baseSpeciesID: Int) async throws -> EvoLine
    func baseSpeciesIndex() async throws -> [BaseSpecies]
    func baseSpecies(id: Int) async throws -> BaseSpecies?
}
