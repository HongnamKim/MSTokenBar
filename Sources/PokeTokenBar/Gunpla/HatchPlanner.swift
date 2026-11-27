import Foundation

/// What the hangar says about each machine, as far as box opening cares.
struct CollectionSnapshot: Sendable {
    /// Machines with a finished run (a hangar record that was not let go). Drives the repeat-growth boost.
    let graduatedMachineIDs: Set<Int>
    /// Grades the player holds per machine: finished runs, runs let go midway, and the one being raised.
    let ownedGrades: [Int: Set<GunplaGrade>]

    /// Finished and holding every released grade. Such a machine stays out of the box until everything
    /// is complete; a grade released later reopens it.
    func isComplete(_ machine: MachineRecord) -> Bool {
        guard graduatedMachineIDs.contains(machine.id) else { return false }
        return machine.grades.allSatisfy((ownedGrades[machine.id] ?? []).contains)
    }
}

extension CompanionState {
    func collectionSnapshot(catalog: MachineCatalog) -> CollectionSnapshot {
        var graduated = Set<Int>()
        var owned: [Int: Set<GunplaGrade>] = [:]
        func own(_ speciesIDs: [Int]) {
            for id in speciesIDs {
                guard let decoded = GunplaID.decode(id), catalog.machine(id: decoded.machineID) != nil else { continue }
                owned[decoded.machineID, default: []].insert(decoded.grade)
            }
        }
        for entry in dex {
            if entry.releasedAt == nil, let machine = catalog.machine(speciesID: entry.finalID) {
                graduated.insert(machine.id)
            }
            own(entry.chainOrder)
        }
        if let active {
            own(Array(active.pathIDs.prefix(active.stageIndex + 1)))
        }
        return CollectionSnapshot(graduatedMachineIDs: graduated, ownedGrades: owned)
    }
}

struct HatchChoice: Equatable {
    let startSpeciesID: Int
    let isVariant: Bool
    let isDuplicatePhase: Bool
}

/// Box opening (spec §5.3): roll variant first, then pick an incomplete machine of that kind by rarity weight,
/// starting just below its first empty grade cell.
///
/// A pre-order is rolled first (§5.2): a guaranteed box or a one-in-four roll opens the target machine,
/// whatever the box's tier or series. Otherwise the box's own roll runs and may still bring the target.
/// `series` narrows the pool to one series and keeps the duplicate phase inside it.
enum HatchPlanner {
    static let rarityWeight: [Rarity: Int] = [.common: 100, .uncommon: 40, .rare: 12, .legendary: 3]

    static func choose(catalog: MachineCatalog, snapshot: CollectionSnapshot, tier: Rarity?,
                       series: String? = nil, preorder: Preorder? = nil, toolLevel: Int,
                       rng: inout any RandomNumberGenerator) -> HatchChoice? {
        if let preorder, let target = catalog.machine(id: preorder.machineID),
           preorder.isGuaranteedNext || rng.next() % Preorder.oddsDenominator == 0 {
            return choice(target, snapshot: snapshot, isDuplicatePhase: snapshot.isComplete(target))
        }
        let eligible = catalog.machines.filter { isEligible($0, tier: tier) && (series == nil || $0.series == series) }
        let fresh = eligible.filter { !snapshot.isComplete($0) }
        let wantVariant = rng.next() % ToolSet.shinyDenominator(toolLevel: toolLevel) == 0

        let isDuplicatePhase = fresh.isEmpty
        let pool = preferred(isDuplicatePhase ? eligible : fresh, variant: wantVariant)
        guard !pool.isEmpty else { return nil }

        // Each hangar slot enters the draw once at its most common eligible rarity.
        let modesBySuit = Dictionary(grouping: pool, by: \.hangarID)
        var seen: Set<Int> = []
        let suits = pool.compactMap { machine -> MachineRecord? in
            guard seen.insert(machine.hangarID).inserted else { return nil }
            return modesBySuit[machine.hangarID]?.min { $0.rarity.sortRank < $1.rarity.sortRank }
        }
        let suit = weightedPick(suits, rng: &rng)
        let modes = modesBySuit[suit.hangarID] ?? [suit]
        let pick: MachineRecord
        if modes.count == 1 {
            pick = suit
        } else if modes.allSatisfy({ $0.rarity == suit.rarity }) {
            pick = modes[Int(rng.next() % UInt64(modes.count))]
        } else {
            pick = weightedPick(modes, rng: &rng)
        }
        return choice(pick, snapshot: snapshot, isDuplicatePhase: isDuplicatePhase)
    }

    private static func choice(_ machine: MachineRecord, snapshot: CollectionSnapshot, isDuplicatePhase: Bool) -> HatchChoice {
        let start = runGrades(machine, snapshot: snapshot)[0]
        return HatchChoice(startSpeciesID: GunplaID.encode(machineID: machine.id, grade: start),
                           isVariant: machine.variantOf != nil,
                           isDuplicatePhase: isDuplicatePhase)
    }

    /// The grades one box run of `machine` raises through, first to last.
    ///
    /// A complete machine (only opened in the duplicate phase) runs its whole released path again.
    /// Any other run starts at the owned grade just below the first empty cell — at that cell when nothing
    /// below it is owned — and ends at the last empty cell, so a grade released after graduation is filled
    /// without raising the grades above it again. A machine let go at its top grade owns every cell but
    /// never finished: it gets that grade alone.
    static func runGrades(_ machine: MachineRecord, snapshot: CollectionSnapshot) -> [GunplaGrade] {
        let grades = machine.grades
        guard !snapshot.isComplete(machine) else { return grades }
        let owned = snapshot.ownedGrades[machine.id] ?? []
        guard let firstEmpty = grades.firstIndex(where: { !owned.contains($0) }),
              let lastEmpty = grades.lastIndex(where: { !owned.contains($0) }) else {
            return [grades[grades.count - 1]]
        }
        return Array(grades[max(0, firstEmpty - 1)...lastEmpty])
    }

    /// Whether a box of this tier still has an incomplete machine (the shop disables it otherwise).
    static func hasCandidates(catalog: MachineCatalog, snapshot: CollectionSnapshot, tier: Rarity?) -> Bool {
        catalog.machines.contains { isEligible($0, tier: tier) && !snapshot.isComplete($0) }
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
