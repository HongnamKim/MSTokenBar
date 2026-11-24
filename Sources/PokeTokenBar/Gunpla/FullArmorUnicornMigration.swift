import Foundation

/// Earlier UC builds stored three green Full Armor grades on the red Destroy track.
/// Only those retired species IDs trigger migration, so importing an updated save is idempotent.
enum FullArmorUnicornMigration {
    private static let movedGrades = Dictionary(uniqueKeysWithValues: [GunplaGrade.sd, .rg, .verka].map { grade in
        (GunplaID.encode(machineID: 117, grade: grade), GunplaID.encode(machineID: 118, grade: grade))
    })

    private static func currentID(_ id: Int) -> Int { movedGrades[id] ?? id }

    private static func names(for ids: [Int]) -> [Int: [String: String]] {
        var result: [Int: [String: String]] = [:]
        for id in ids {
            if let grade = GunplaID.decode(id)?.grade, let machine = MachineCatalog.shared.machine(speciesID: id) {
                result[id] = machine.names.mapValues { "\(grade.label) \($0)" }
            }
        }
        return result
    }

    static func apply(to state: inout CompanionState) {
        state.representativeSpeciesID = state.representativeSpeciesID.map(currentID)
        state.pendingHatchID = state.pendingHatchID.map(currentID)
        for i in state.dex.indices {
            let old = state.dex[i]
            guard old.chainOrder.contains(where: { movedGrades[$0] != nil }) else { continue }
            let chain = old.chainOrder.map(currentID)
            state.dex[i].chainOrder = chain
            state.dex[i].baseID = currentID(old.baseID)
            state.dex[i].finalID = currentID(old.finalID)
            state.dex[i].names = names(for: chain)
            state.dex[i].namesVersion = DexEntry.currentNamesVersion
            if state.collectedFinals.remove("\(old.baseID):\(old.finalID)") != nil {
                state.collectedFinals.insert("\(state.dex[i].baseID):\(state.dex[i].finalID)")
            }
        }

        guard var active = state.active,
              GunplaID.decode(active.baseID)?.machineID == 117,
              (active.pathIDs + active.plannedPathIDs).contains(where: { movedGrades[$0] != nil }) else { return }
        let id = currentID(active.currentID)
        guard let grade = GunplaID.decode(id)?.grade, let machine = MachineCatalog.shared.machine(speciesID: id) else { return }

        // The old run could alternate colors. Keep the earned prefix in the hangar before
        // resuming from the current grade, with all accumulated tokens and individual traits.
        let earlier = active.pathIDs.prefix(active.stageIndex).map(currentID)
        if let first = earlier.first, let last = earlier.last {
            let now = Date()
            state.dex.append(DexEntry(baseID: first, finalID: last, chainOrder: earlier,
                                      rarity: active.rarity, caughtAt: nil, isShiny: active.isShiny,
                                      names: names(for: earlier), releasedAt: now, prayers: active.prayers))
        }
        active.baseID = id
        active.pathIDs = [id]
        active.plannedPathIDs = machine.grades.filter { $0 >= grade }.map { GunplaID.encode(machineID: machine.id, grade: $0) }
        active.stageIndex = 0
        active.totalForms = active.plannedPathIDs.count
        state.active = active
    }
}
