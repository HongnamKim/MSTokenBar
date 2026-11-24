import XCTest
@testable import PokeTokenBar

final class HatchPlannerTests: XCTestCase {
    private let catalog = MachineCatalog.allBundled
    private var allIDs: Set<Int> { Set(catalog.machines.map(\.id)) }
    private var variantIDs: Set<Int> { Set(catalog.machines.filter(\.isVariant).map(\.id)) }
    private var allBaseIDs: Set<Int> { allIDs.subtracting(variantIDs) }

    /// `graduated` machines finished a run and hold every released grade; `owned` adds the grades of
    /// machines let go midway.
    private func snapshot(graduated: Set<Int> = [], owned: [Int: Set<GunplaGrade>] = [:]) -> CollectionSnapshot {
        var grades = owned
        for id in graduated { grades[id] = Set(catalog.machine(id: id)!.grades) }
        return CollectionSnapshot(graduatedMachineIDs: graduated, ownedGrades: grades)
    }

    private func choose(_ snapshot: CollectionSnapshot, tier: Rarity? = nil, toolLevel: Int = 0,
                        rng: inout any RandomNumberGenerator) -> HatchChoice? {
        HatchPlanner.choose(catalog: catalog, snapshot: snapshot, tier: tier, toolLevel: toolLevel, rng: &rng)
    }

    /// First value decides the variant roll (`% denominator == 0` → variant), second the weighted pick.
    private func choose(_ snapshot: CollectionSnapshot, tier: Rarity? = nil, toolLevel: Int = 0,
                        sequence: [UInt64]) -> HatchChoice? {
        var rng: any RandomNumberGenerator = SequenceRNG(sequence)
        return choose(snapshot, tier: tier, toolLevel: toolLevel, rng: &rng)
    }

    private func machineID(_ choice: HatchChoice?) -> Int? {
        choice.flatMap { GunplaID.decode($0.startSpeciesID)?.machineID }
    }

    func test_neverPicksGraduatedMachine() {
        var rng: any RandomNumberGenerator = SeededRNG(seed: 7)
        let snap = snapshot(graduated: allIDs.subtracting([3]))
        for _ in 0..<1000 {
            let choice = choose(snap, rng: &rng)
            XCTAssertEqual(machineID(choice), 3)
            XCTAssertEqual(choice?.isDuplicatePhase, false)
        }
    }

    func test_variantRollPicksFromVariantPool() {
        for pick: UInt64 in [0, 5, 11, 12, 23, 100, 12_345] {
            let choice = choose(snapshot(), sequence: [0, pick])
            XCTAssertEqual(choice?.isVariant, true)
            XCTAssertTrue(variantIDs.contains(machineID(choice) ?? -1), "pick=\(pick)")
            XCTAssertEqual(choice?.isDuplicatePhase, false)
        }
    }

    func test_variantsObtainableAfterBaseGraduated() {
        let choice = choose(snapshot(graduated: [2]), sequence: [0, 0])
        XCTAssertEqual(machineID(choice), 3)
        XCTAssertEqual(choice?.isVariant, true)
    }

    func test_emptyVariantPoolFallsBackToBases() {
        for pick: UInt64 in [0, 7, 99, 1_000] {
            let choice = choose(snapshot(graduated: variantIDs), sequence: [0, pick])
            XCTAssertEqual(choice?.isVariant, false)
            XCTAssertTrue(allBaseIDs.contains(machineID(choice) ?? -1))
            XCTAssertEqual(choice?.isDuplicatePhase, false)
        }
    }

    func test_emptyBasePoolFallsBackToVariants() {
        for pick: UInt64 in [0, 7, 99, 1_000] {
            let choice = choose(snapshot(graduated: allBaseIDs), sequence: [1, pick])
            XCTAssertEqual(choice?.isVariant, true)
            XCTAssertTrue(variantIDs.contains(machineID(choice) ?? -1))
            XCTAssertEqual(choice?.isDuplicatePhase, false)
        }
    }

    func test_allGraduatedEntersDuplicatePhase() {
        var rng: any RandomNumberGenerator = SeededRNG(seed: 11)
        let snap = snapshot(graduated: allIDs)
        for _ in 0..<500 {
            guard let choice = choose(snap, rng: &rng),
                  let decoded = GunplaID.decode(choice.startSpeciesID),
                  let machine = catalog.machine(id: decoded.machineID) else {
                return XCTFail("expected a duplicate-phase choice")
            }
            XCTAssertTrue(choice.isDuplicatePhase)
            XCTAssertEqual(decoded.grade, machine.grades.first)
            XCTAssertEqual(choice.isVariant, machine.isVariant)
        }
    }

    func test_resumesFromHighestReachedGrade() {
        let snap = snapshot(graduated: allIDs.subtracting([1]), owned: [1: [.sd, .hg]])
        for sequence: [UInt64] in [[1, 0], [0, 0], [5, 77]] {
            let choice = choose(snap, sequence: sequence)
            XCTAssertEqual(choice?.startSpeciesID, GunplaID.encode(machineID: 1, grade: .hg))
            XCTAssertEqual(choice?.isDuplicatePhase, false)
        }
    }

    func test_resumeAtFinalGradeGivesSingleStageLine() async throws {
        let snap = snapshot(graduated: allIDs.subtracting([1]), owned: [1: [.sd, .hg, .rg, .mg, .verka, .pg]])
        let choice = try XCTUnwrap(choose(snap, sequence: [1, 0]))
        XCTAssertEqual(choice.startSpeciesID, GunplaID.encode(machineID: 1, grade: .pg))
        let line = try await catalog.line(baseSpeciesID: choice.startSpeciesID)
        XCTAssertEqual(line.totalForms, 1)
    }

    func test_tierFiltersCandidates() {
        var rng: any RandomNumberGenerator = SeededRNG(seed: 3)
        for _ in 0..<500 {
            let id = machineID(choose(snapshot(), tier: .rare, rng: &rng))
            let rarity = id.flatMap { catalog.machine(id: $0)?.rarity }
            XCTAssertTrue([Rarity.rare, .legendary].contains(rarity ?? .common), "id=\(String(describing: id))")
        }
    }

    func test_toolLevelChangesVariantOdds() {
        XCTAssertEqual(ToolSet.shinyDenominator(toolLevel: 0), 32)
        XCTAssertEqual(ToolSet.shinyDenominator(toolLevel: 4), 12)
        XCTAssertEqual(choose(snapshot(), toolLevel: 0, sequence: [32, 0])?.isVariant, true)
        XCTAssertEqual(choose(snapshot(), toolLevel: 0, sequence: [12, 0])?.isVariant, false)
        XCTAssertEqual(choose(snapshot(), toolLevel: 4, sequence: [12, 0])?.isVariant, true)
        XCTAssertEqual(choose(snapshot(), toolLevel: 4, sequence: [32, 0])?.isVariant, false)
    }

    func test_toolLevelIsClampedIntoDenominatorTable() {
        XCTAssertEqual(ToolSet.denominators, [32, 26, 21, 16, 12])
        XCTAssertEqual(ToolSet.shinyDenominator(toolLevel: -3), 32)
        XCTAssertEqual(ToolSet.shinyDenominator(toolLevel: 99), 12)
    }

    func test_rarityWeightsFavourCommonMachines() {
        XCTAssertEqual(HatchPlanner.rarityWeight, [.common: 100, .uncommon: 40, .rare: 12, .legendary: 3])
        // Bases in catalog order: 1 rare(12) | 2 common(100) | 4 common(100) | ... → pick 0..11 is #1, 12 is #2.
        XCTAssertEqual(machineID(choose(snapshot(), sequence: [1, 11])), 1)
        XCTAssertEqual(machineID(choose(snapshot(), sequence: [1, 12])), 2)
    }

    func test_twoModesShareOneSuitWeightAndOnlyUnfinishedModesCanDrop() {
        // Unit 1 has weight 3 and Sinanju has weight 12.
        let bothModes = snapshot(graduated: allIDs.subtracting([11, 100, 103]))
        XCTAssertEqual(machineID(choose(bothModes, sequence: [1, 2, 0])), 11)
        XCTAssertEqual(machineID(choose(bothModes, sequence: [1, 2, 1])), 100)
        XCTAssertEqual(machineID(choose(bothModes, sequence: [1, 3, 0])), 103)

        let onlyDestroy = snapshot(graduated: allIDs.subtracting([100]))
        XCTAssertEqual(machineID(choose(onlyDestroy, sequence: [1, 0])), 100)
    }

    func test_hasCandidatesReflectsTierAndGraduation() {
        XCTAssertTrue(HatchPlanner.hasCandidates(catalog: catalog, snapshot: snapshot(), tier: nil))
        let rarePlus = Set(catalog.machines.filter { $0.rarity.sortRank >= Rarity.rare.sortRank }.map(\.id))
        XCTAssertFalse(HatchPlanner.hasCandidates(catalog: catalog, snapshot: snapshot(graduated: rarePlus), tier: .rare))
        XCTAssertTrue(HatchPlanner.hasCandidates(catalog: catalog, snapshot: snapshot(graduated: rarePlus), tier: .uncommon))
        XCTAssertFalse(HatchPlanner.hasCandidates(catalog: catalog, snapshot: snapshot(graduated: allIDs), tier: nil))
    }

    func test_collectionSnapshotCollectsOwnedGradesAndFinishedMachines() {
        var state = CompanionState()
        let id = { GunplaID.encode(machineID: $0, grade: $1) }
        // 2 graduated at PG after being released once earlier at HG — both records count as owned grades.
        state.dex.append(DexEntry(baseID: id(2, .sd), finalID: id(2, .hg), chainOrder: [id(2, .sd), id(2, .hg)],
                                  rarity: .common, caughtAt: nil, releasedAt: Date()))
        state.dex.append(DexEntry(baseID: id(2, .hg), finalID: id(2, .pg),
                                  chainOrder: [.hg, .rg, .mg, .pg].map { id(2, $0) },
                                  rarity: .common, caughtAt: nil))
        // 1 released twice — never finished, every reached grade is owned.
        state.dex.append(DexEntry(baseID: id(1, .sd), finalID: id(1, .rg), chainOrder: [.sd, .hg, .rg].map { id(1, $0) },
                                  rarity: .rare, caughtAt: nil, releasedAt: Date()))
        state.dex.append(DexEntry(baseID: id(1, .sd), finalID: id(1, .hg), chainOrder: [id(1, .sd), id(1, .hg)],
                                  rarity: .rare, caughtAt: nil, releasedAt: Date()))
        // Active 4 has reached MG (stage 1 of hg→mg).
        state.active = MonState(baseID: id(4, .hg), pathIDs: [id(4, .hg), id(4, .mg)], stageIndex: 1,
                                usedAtStage: 0, rarity: .common, totalForms: 2)

        let snap = state.collectionSnapshot(catalog: catalog)
        XCTAssertEqual(snap.graduatedMachineIDs, [2])
        XCTAssertEqual(snap.ownedGrades, [2: [.sd, .hg, .rg, .mg, .pg], 1: [.sd, .hg, .rg], 4: [.hg, .mg]])
        XCTAssertTrue(snap.isComplete(catalog.machine(id: 2)!))
        XCTAssertFalse(snap.isComplete(catalog.machine(id: 1)!))
    }

    // MARK: the grades one run raises through

    private func run(_ grades: [GunplaGrade], owned: Set<GunplaGrade>, graduated: Bool) -> [GunplaGrade] {
        let machine = MachineRecord(id: 1, modelNumber: "X-1", names: [:], series: "first", faction: "efsf",
                                    rarity: .common, grades: grades, gradeSources: nil, variantOf: nil, sprites: nil)
        return HatchPlanner.runGrades(machine, snapshot: CollectionSnapshot(
            graduatedMachineIDs: graduated ? [1] : [], ownedGrades: [1: owned]))
    }

    func test_runCoversEveryGradeOfAMachineNeverOpened() {
        XCTAssertEqual(run([.sd, .hg, .mg], owned: [], graduated: false), [.sd, .hg, .mg])
    }

    func test_runResumesFromTheGradeReachedLastTime() {
        XCTAssertEqual(run([.sd, .hg, .rg, .mg, .pg], owned: [.sd, .hg], graduated: false), [.hg, .rg, .mg, .pg])
        // A reached grade the catalog dropped since is simply not a cell any more.
        XCTAssertEqual(run([.sd, .hg, .mg, .pg], owned: [.sd, .hg, .rg], graduated: false), [.hg, .mg, .pg])
    }

    func test_runOfAMachineLetGoAtItsTopGradeIsThatGradeAlone() {
        XCTAssertEqual(run([.sd, .hg, .mg], owned: [.sd, .hg, .mg], graduated: false), [.mg])
    }

    func test_runOfACompleteMachineIsTheWholePathAgain() {
        XCTAssertEqual(run([.sd, .hg, .mg], owned: [.sd, .hg, .mg], graduated: true), [.sd, .hg, .mg])
    }

    /// Trigger branch: graduated (a finished run exists) AND a released grade is not owned.
    func test_runOfAGraduatedMachineFillsOnlyTheEmptyCells() {
        let owned: Set<GunplaGrade> = [.sd, .hg, .mg, .pg]
        XCTAssertEqual(run([.sd, .hg, .rg, .mg, .pg], owned: owned, graduated: true), [.hg, .rg], "one gap")
        XCTAssertEqual(run([.sd, .mgsd, .hg, .rg, .mg, .pg], owned: owned, graduated: true),
                       [.sd, .mgsd, .hg, .rg], "two gaps: through the owned grade between them")
        XCTAssertEqual(run([.sd, .hg, .mg, .pg], owned: [.sd, .hg, .mg], graduated: true), [.mg, .pg], "new top grade")
        XCTAssertEqual(run([.sd, .hg, .mg], owned: [.hg, .mg], graduated: true), [.sd], "new lowest grade")
    }

    func test_graduatedMachineWithAnEmptyCellIsPickedAgainFromJustBelowIt() {
        // Machine 4 (GM) is released in HG and MG; the player finished it when only HG counted.
        let snap = CollectionSnapshot(graduatedMachineIDs: allIDs,
                                      ownedGrades: snapshot(graduated: allIDs.subtracting([4])).ownedGrades
                                          .merging([4: [.hg]]) { $1 })
        XCTAssertTrue(HatchPlanner.hasCandidates(catalog: catalog, snapshot: snap, tier: nil))
        var rng: any RandomNumberGenerator = SeededRNG(seed: 5)
        for _ in 0..<200 {
            let choice = choose(snap, rng: &rng)
            XCTAssertEqual(choice?.startSpeciesID, GunplaID.encode(machineID: 4, grade: .hg))
            XCTAssertEqual(choice?.isDuplicatePhase, false)
        }
    }
}
