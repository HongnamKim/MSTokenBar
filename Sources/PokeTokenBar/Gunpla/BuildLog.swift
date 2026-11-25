import Foundation

/// Where an amount of growth came from.
enum BuildIncrement: Equatable, Sendable {
    case providers([String: Int])   // actual tokens, keyed by UsageProvider.id
    case sandpaper(Int)             // growth credits from sponge sandpaper
    case unattributed(Int)          // source unknown

    /// Sum of the positive amounts; what `usedAtStage` grows by.
    var total: Int {
        switch self {
        case .providers(let tokens): return tokens.values.reduce(0) { $0 + max(0, $1) }
        case .sandpaper(let n), .unattributed(let n): return max(0, n)
        }
    }
}

/// Growth accumulated while one grade of the machine was being built.
struct BuildStage: Codable, Sendable, Equatable {
    /// GunplaID (machine x grade). A save migration that rewrites the species ids of `chainOrder` or
    /// `pathIDs` (see `FullArmorUnicornMigration`) must rewrite this id too.
    var speciesID: Int
    var reachedAt: Date?            // nil = unknown
    var tokensByProvider: [String: Int]
    var sandpaper: Int
    var unattributed: Int

    init(speciesID: Int, reachedAt: Date?, tokensByProvider: [String: Int] = [:],
         sandpaper: Int = 0, unattributed: Int = 0) {
        self.speciesID = speciesID
        self.reachedAt = reachedAt
        self.tokensByProvider = tokensByProvider
        self.sandpaper = sandpaper
        self.unattributed = unattributed
    }
}

/// Per-build record of where each grade's growth came from. The buckets of a stage never have to add up
/// to `usedAtStage` (a difficulty change rescales one but not the other).
struct BuildLog: Codable, Sendable, Equatable {
    var openedAt: Date?             // nil = the record began mid-build
    var stages: [BuildStage]

    static func opened(speciesID: Int, at: Date) -> BuildLog {
        BuildLog(openedAt: at, stages: [BuildStage(speciesID: speciesID, reachedAt: at)])
    }

    static func resumed(speciesID: Int, banked: Int) -> BuildLog {
        BuildLog(openedAt: nil, stages: [BuildStage(speciesID: speciesID, reachedAt: nil, unattributed: banked)])
    }

    mutating func add(_ increment: BuildIncrement, to speciesID: Int) {
        let index = stageIndex(for: speciesID, reachedAt: nil)
        switch increment {
        case .providers(let tokens):
            for (key, value) in tokens where value > 0 {
                stages[index].tokensByProvider[key] = Self.sum(stages[index].tokensByProvider[key] ?? 0, value)
            }
        case .sandpaper(let n):
            if n > 0 { stages[index].sandpaper = Self.sum(stages[index].sandpaper, n) }
        case .unattributed(let n):
            if n > 0 { stages[index].unattributed = Self.sum(stages[index].unattributed, n) }
        }
    }

    /// Moves the overflow share (`banked - threshold`) of every bucket from one grade to the next.
    mutating func advance(from: Int, to: Int, banked: Int, threshold: Int, at: Date) {
        let toIndex = stageIndex(for: to, reachedAt: at)
        guard from != to, banked > 0, let fromIndex = stages.firstIndex(where: { $0.speciesID == from })
        else { return }
        let overflow = min(max(0, banked - threshold), banked)
        func portion(_ value: Int) -> Int { Self.portion(of: value, share: overflow, banked: banked) }
        for (key, value) in stages[fromIndex].tokensByProvider {
            let moved = portion(value)
            guard moved > 0 else { continue }
            stages[fromIndex].tokensByProvider[key] = value - moved
            stages[toIndex].tokensByProvider[key] = Self.sum(stages[toIndex].tokensByProvider[key] ?? 0, moved)
        }
        let sandpaper = portion(stages[fromIndex].sandpaper)
        stages[fromIndex].sandpaper -= sandpaper
        stages[toIndex].sandpaper = Self.sum(stages[toIndex].sandpaper, sandpaper)
        let unattributed = portion(stages[fromIndex].unattributed)
        stages[fromIndex].unattributed -= unattributed
        stages[toIndex].unattributed = Self.sum(stages[toIndex].unattributed, unattributed)
    }

    func keeping(_ speciesIDs: [Int]) -> BuildLog {
        BuildLog(openedAt: openedAt, stages: stages.filter { speciesIDs.contains($0.speciesID) })
    }

    func clamped(to limit: Int) -> BuildLog {
        func bound(_ v: Int) -> Int { min(max(0, v), limit) }
        var copy = self
        for i in copy.stages.indices {
            copy.stages[i].tokensByProvider = copy.stages[i].tokensByProvider.mapValues(bound)
            copy.stages[i].sandpaper = bound(copy.stages[i].sandpaper)
            copy.stages[i].unattributed = bound(copy.stages[i].unattributed)
        }
        return copy
    }

    /// Index of the first stage for `speciesID`, appending an empty one when there is none.
    private mutating func stageIndex(for speciesID: Int, reachedAt: Date?) -> Int {
        if let index = stages.firstIndex(where: { $0.speciesID == speciesID }) { return index }
        stages.append(BuildStage(speciesID: speciesID, reachedAt: reachedAt))
        return stages.count - 1
    }

    private static func sum(_ a: Int, _ b: Int) -> Int {
        let (result, overflow) = a.addingReportingOverflow(b)
        return overflow ? Int.max : result
    }

    /// floor(value x share / banked). Both factors can reach 10^15, so the product needs full width.
    private static func portion(of value: Int, share: Int, banked: Int) -> Int {
        guard value > 0, share > 0, banked > 0 else { return 0 }
        let product = value.multipliedFullWidth(by: min(share, banked))
        return banked.dividingFullWidth(product).quotient
    }
}
