import XCTest
@testable import PokeTokenBar

/// Stores loaded from a written save, so the load-time sanitizing runs. 50B spendable unless the state says otherwise.
@MainActor
enum PreorderFixture {
    static let catalog = MachineCatalog.allBundled
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static let rx78 = 1, zaku = 2, charZaku = 3, gouf = 5, nu = 8, unicorn = 11, unicornDestroy = 100, unicornAwakened = 115

    static func id(_ machineID: Int, _ grade: GunplaGrade) -> Int {
        GunplaID.encode(machineID: machineID, grade: grade)
    }

    static func store(_ state: CompanionState = CompanionState(),
                      rng: any RandomNumberGenerator = SeededRNG(seed: 7)) throws -> CompanionStore {
        var state = state
        state.installBaselineSet = true
        if state.usedSinceInstall == 0 { state.usedSinceInstall = 50_000_000_000 }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preorder-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: url)
        let fixedNow = now
        return CompanionStore(provider: catalog, clock: { fixedNow }, fileURL: url, rng: rng,
                              defaults: UserDefaults(suiteName: "preorder-\(UUID().uuidString)")!)
    }

    /// First grade, plan = every released grade.
    static func building(_ machineID: Int) -> MonState {
        let machine = catalog.machine(id: machineID)!
        let ids = machine.grades.map { id(machineID, $0) }
        return MonState(baseID: ids[0], pathIDs: [ids[0]], plannedPathIDs: ids, stageIndex: 0, usedAtStage: 0,
                        rarity: machine.rarity, totalForms: ids.count)
    }

    /// Graduated with every released grade.
    static func finished(_ machineID: Int) -> DexEntry {
        let machine = catalog.machine(id: machineID)!
        let ids = machine.grades.map { id(machineID, $0) }
        return DexEntry(baseID: ids[0], finalID: ids[ids.count - 1], chainOrder: ids,
                        rarity: machine.rarity, caughtAt: now)
    }

    static func use(_ s: CompanionStore, _ today: Int) {
        s.update(todayTokensByProvider: ["test": today], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
    }

    /// Opens the box with the store's own update/hatch path (prefetch Tasks may run in between).
    static func openBox(_ s: CompanionStore) async {
        use(s, 0)
        use(s, s.eggHatchThreshold)
        let deadline = Date().addingTimeInterval(2)
        while s.state.active == nil, Date() < deadline {
            await s.hatchIfNeeded()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    static func machineID(_ speciesID: Int?) -> Int? {
        speciesID.flatMap { GunplaID.decode($0)?.machineID }
    }
}
