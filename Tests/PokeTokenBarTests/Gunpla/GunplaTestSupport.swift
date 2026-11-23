import Foundation
@testable import PokeTokenBar

/// Replays a fixed sequence of raw values (cycling), so a test can pin exactly which rolls a draw sees.
struct SequenceRNG: RandomNumberGenerator {
    private let values: [UInt64]
    private var index = 0

    init(_ values: [UInt64]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    mutating func next() -> UInt64 {
        defer { index = (index + 1) % values.count }
        return values[index]
    }
}

extension MachineCatalog {
    /// Every bundled machine, art or not. Tests use the development machines (Zeta, CCA, UC) as fixtures,
    /// while the app's `shared` catalog only serves machines with art.
    static let allBundled: MachineCatalog = try! bundled()
}
