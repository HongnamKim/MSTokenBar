import Foundation

/// What the hangar says about each machine, as far as box opening cares.
struct CollectionSnapshot: Sendable {
    /// Machines raised to their final grade (graduated). They never come out of a box again
    /// until everything is graduated.
    let graduatedMachineIDs: Set<Int>
    /// Highest grade reached by machines that were released before graduating. Graduated machines are absent.
    let highestReachedGrade: [Int: GunplaGrade]
}

extension CompanionState {
    func collectionSnapshot(catalog: MachineCatalog) -> CollectionSnapshot {
        var graduated = Set<Int>()
        var highest: [Int: GunplaGrade] = [:]
        func reach(_ speciesIDs: [Int]) {
            for id in speciesIDs {
                guard let decoded = GunplaID.decode(id), catalog.machine(decoded.machineID) != nil else { continue }
                highest[decoded.machineID] = max(highest[decoded.machineID] ?? decoded.grade, decoded.grade)
            }
        }
        for entry in dex {
            if entry.releasedAt == nil, let machine = catalog.machine(speciesID: entry.finalID) {
                graduated.insert(machine.id)
            }
            reach(entry.chainOrder)
        }
        if let active {
            reach(Array(active.pathIDs.prefix(active.stageIndex + 1)))
        }
        for id in graduated { highest[id] = nil }
        return CollectionSnapshot(graduatedMachineIDs: graduated, highestReachedGrade: highest)
    }
}

struct HatchChoice: Equatable {
    let startSpeciesID: Int
    let isVariant: Bool
    let isDuplicatePhase: Bool
}

/// Box opening (spec §5.3): roll variant first, then pick an ungraduated machine of that kind by rarity weight,
/// starting from the grade it reached last time.
enum HatchPlanner {
    static let rarityWeight: [Rarity: Int] = [.common: 100, .uncommon: 40, .rare: 12, .legendary: 3]

    static func choose(catalog: MachineCatalog, snapshot: CollectionSnapshot, tier: Rarity?, toolLevel: Int,
                       rng: inout any RandomNumberGenerator) -> HatchChoice? {
        let eligible = catalog.machines.filter { isEligible($0, tier: tier) }
        let fresh = eligible.filter { !snapshot.graduatedMachineIDs.contains($0.id) }
        let wantVariant = rng.next() % ToolSet.shinyDenominator(toolLevel: toolLevel) == 0

        let isDuplicatePhase = fresh.isEmpty
        let pool = preferred(isDuplicatePhase ? eligible : fresh, variant: wantVariant)
        guard !pool.isEmpty else { return nil }

        let pick = weightedPick(pool, rng: &rng)
        let start: GunplaGrade
        if !isDuplicatePhase, let reached = snapshot.highestReachedGrade[pick.id] {
            // A grade dropped from the catalog since it was reached falls back to the nearest released one below.
            start = pick.grades.last(where: { $0 <= reached }) ?? pick.grades[0]
        } else {
            start = pick.grades[0]
        }
        return HatchChoice(startSpeciesID: GunplaID.encode(machineID: pick.id, grade: start),
                           isVariant: pick.variantOf != nil,
                           isDuplicatePhase: isDuplicatePhase)
    }

    /// Whether a box of this tier still has a machine that has not graduated (the shop disables it otherwise).
    static func hasCandidates(catalog: MachineCatalog, snapshot: CollectionSnapshot, tier: Rarity?) -> Bool {
        catalog.machines.contains { isEligible($0, tier: tier) && !snapshot.graduatedMachineIDs.contains($0.id) }
    }

    private static func isEligible(_ machine: MachineRecord, tier: Rarity?) -> Bool {
        tier.map { machine.rarity.sortRank >= $0.sortRank } ?? true
    }

    /// The rolled kind's machines, or the other kind's when none are left.
    private static func preferred(_ machines: [MachineRecord], variant: Bool) -> [MachineRecord] {
        let wanted = machines.filter { $0.isVariant == variant }
        return wanted.isEmpty ? machines : wanted
    }

    /// Exactly one roll over the cumulative rarity weights.
    private static func weightedPick(_ pool: [MachineRecord], rng: inout any RandomNumberGenerator) -> MachineRecord {
        let weights = pool.map { rarityWeight[$0.rarity] ?? 1 }
        var r = Int(rng.next() % UInt64(weights.reduce(0, +)))
        for (machine, weight) in zip(pool, weights) {
            r -= weight
            if r < 0 { return machine }
        }
        return pool[pool.count - 1]
    }
}
