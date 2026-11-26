import Foundation

/// One hangar cell = one machine, with the released grades the player owns.
struct HangarCell: Identifiable, Sendable {
    let machineID: Int
    let ownedGrades: Set<GunplaGrade>
    let releasedGrades: [GunplaGrade]
    let isVariant: Bool
    /// The machine the player is raising right now (any of its reached grades is the current one).
    let isRaising: Bool

    var id: Int { machineID }
    /// False for a silhouette cell: a catalog machine the player has not built in any grade yet.
    var isBuilt: Bool { !ownedGrades.isEmpty }
}

/// The grid groups independent growth tracks after applying its search and sort order.
struct HangarEntry: Identifiable {
    let id: Int
    let cells: [HangarCell]

    func displayed(preferredID: Int?) -> HangarCell {
        cells.first { $0.isBuilt && $0.machineID == preferredID }
            ?? cells.first(where: \.isRaising)
            ?? cells.first(where: \.isBuilt)
            ?? cells[0]
    }

    static func grouped(_ cells: [HangarCell], catalog: MachineCatalog) -> [HangarEntry] {
        func groupID(_ cell: HangarCell) -> Int { catalog.machine(id: cell.machineID)?.hangarID ?? cell.machineID }
        let groups = Dictionary(grouping: cells, by: groupID)
        var seen: Set<Int> = []
        return cells.compactMap { cell in
            let id = groupID(cell)
            guard seen.insert(id).inserted, let members = groups[id] else { return nil }
            return HangarEntry(id: id, cells: members)
        }
    }
}

/// Owned/total progress for one series. A cell is a (machine, released grade) pair; base machines and
/// variants (전용기) are counted separately so each has its own badge. Cells decide the badges; the
/// series list leads with machines, because the grid shows one square per machine.
struct SeriesCompletion: Identifiable, Sendable, Equatable {
    let seriesID: String
    let ownedCells: Int
    let totalCells: Int
    let variantOwnedCells: Int
    let variantTotalCells: Int
    /// Base machines built in at least one released grade, and how many the series has. A mode is a
    /// machine of its own: it grows on its own track even though it shares a hangar entry.
    let builtMachines: Int
    let totalMachines: Int

    var isComplete: Bool { totalCells > 0 && ownedCells >= totalCells }
    /// A series without variants has nothing to complete, so it never earns the variant badge.
    var isVariantComplete: Bool { variantTotalCells > 0 && variantOwnedCells >= variantTotalCells }
    /// The series' filter has something to show: a built machine, or base-machine silhouettes.
    /// Unbuilt 전용기 stay hidden, so a series of only those shows nothing until one is built.
    var hasHangarCells: Bool { ownedCells + variantOwnedCells > 0 || totalCells > 0 }
    var id: String { seriesID }
}

/// A cosmetic completion achievement. Cases carry a stable `notificationKey` because the
/// "already notified" set is persisted — the keys must never drift across releases.
/// Keys from the Pokémon build (`region.*`, `unown`, `national*`) are no longer produced and are ignored.
enum DexBadge: Equatable, Hashable, Sendable {
    case series(String)
    case seriesVariant(String)
    case all
    case allVariant

    var notificationKey: String {
        switch self {
        case .series(let id): return "series.\(id)"
        case .seriesVariant(let id): return "seriesVariant.\(id)"
        case .all: return "all"
        case .allVariant: return "allVariant"
        }
    }

    /// The series a per-series badge belongs to.
    var seriesID: String? {
        switch self {
        case .series(let id), .seriesVariant(let id): return id
        case .all, .allVariant: return nil
        }
    }
}

/// Pure completion math over hangar cells, kept store-independent so it is unit-testable.
enum HangarProgress {
    /// Per-series progress in catalog series order. Owned grades a machine was never released in add nothing.
    static func completions(owned: [HangarCell], catalog: MachineCatalog) -> [SeriesCompletion] {
        var ownedByMachine: [Int: Set<GunplaGrade>] = [:]
        for cell in owned { ownedByMachine[cell.machineID, default: []].formUnion(cell.ownedGrades) }
        return catalog.series.sorted { $0.order < $1.order }.map { series in
            var owned = 0, total = 0, variantOwned = 0, variantTotal = 0, built = 0, machines = 0
            for machine in catalog.machines where machine.series == series.id {
                let have = ownedByMachine[machine.id].map { $0.intersection(machine.grades).count } ?? 0
                if machine.isVariant {
                    variantOwned += have
                    variantTotal += machine.grades.count
                } else {
                    owned += have
                    total += machine.grades.count
                    if have > 0 { built += 1 }
                    machines += 1
                }
            }
            return SeriesCompletion(seriesID: series.id, ownedCells: owned, totalCells: total,
                                    variantOwnedCells: variantOwned, variantTotalCells: variantTotal,
                                    builtMachines: built, totalMachines: machines)
        }
    }

    /// Every badge currently earned, in a stable order: per series (base, then variant), then all, allVariant.
    static func earnedBadges(_ completions: [SeriesCompletion]) -> [DexBadge] {
        var badges: [DexBadge] = []
        for completion in completions {
            if completion.isComplete { badges.append(.series(completion.seriesID)) }
            if completion.isVariantComplete { badges.append(.seriesVariant(completion.seriesID)) }
        }
        let withBase = completions.filter { $0.totalCells > 0 }
        if !withBase.isEmpty, withBase.allSatisfy(\.isComplete) { badges.append(.all) }
        let withVariants = completions.filter { $0.variantTotalCells > 0 }
        if !withVariants.isEmpty, withVariants.allSatisfy(\.isVariantComplete) { badges.append(.allVariant) }
        return badges
    }

    /// Badges that are earned but not yet announced, in the stable badge order.
    static func newlyEarnedBadges(earned: [DexBadge], alreadyNotified: Set<String>) -> [DexBadge] {
        earned.filter { !alreadyNotified.contains($0.notificationKey) }
    }
}
