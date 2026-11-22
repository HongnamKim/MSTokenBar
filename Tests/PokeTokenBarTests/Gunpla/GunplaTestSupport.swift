import Foundation

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
