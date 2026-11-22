import XCTest
@testable import PokeTokenBar

final class HatchPlannerTests: XCTestCase {
    private let catalog = MachineCatalog.shared
    private let allBaseIDs: Set<Int> = [1, 2, 4, 5, 6, 7, 8, 9, 10, 11]
    private let allIDs = Set(1...12)

    private func snapshot(graduated: Set<Int> = [], reached: [Int: GunplaGrade] = [:]) -> CollectionSnapshot {
        CollectionSnapshot(graduatedMachineIDs: graduated, highestReachedGrade: reached)
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
        let snap = snapshot(graduated: Set(1...11))
        for _ in 0..<1000 {
            let choice = choose(snap, rng: &rng)
            XCTAssertEqual(machineID(choice), 12)
            XCTAssertEqual(choice?.isDuplicatePhase, false)
        }
    }

    func test_variantRollPicksFromVariantPool() {
        for pick: UInt64 in [0, 5, 11, 12, 23, 100, 12_345] {
            let choice = choose(snapshot(), sequence: [0, pick])
            XCTAssertEqual(choice?.isVariant, true)
            XCTAssertTrue([3, 12].contains(machineID(choice) ?? -1), "pick=\(pick)")
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
            let choice = choose(snapshot(graduated: [3, 12]), sequence: [0, pick])
            XCTAssertEqual(choice?.isVariant, false)
            XCTAssertTrue(allBaseIDs.contains(machineID(choice) ?? -1))
            XCTAssertEqual(choice?.isDuplicatePhase, false)
        }
    }

    func test_emptyBasePoolFallsBackToVariants() {
        for pick: UInt64 in [0, 7, 99, 1_000] {
            let choice = choose(snapshot(graduated: allBaseIDs), sequence: [1, pick])
            XCTAssertEqual(choice?.isVariant, true)
            XCTAssertTrue([3, 12].contains(machineID(choice) ?? -1))
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
        let snap = snapshot(graduated: allIDs.subtracting([1]), reached: [1: .hg])
        for sequence: [UInt64] in [[1, 0], [0, 0], [5, 77]] {
            let choice = choose(snap, sequence: sequence)
            XCTAssertEqual(choice?.startSpeciesID, GunplaID.encode(machineID: 1, grade: .hg))
            XCTAssertEqual(choice?.isDuplicatePhase, false)
        }
    }

    func test_resumeAtFinalGradeGivesSingleStageLine() async throws {
        let snap = snapshot(graduated: allIDs.subtracting([1]), reached: [1: .pg])
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

    func test_hasCandidatesReflectsTierAndGraduation() {
        XCTAssertTrue(HatchPlanner.hasCandidates(catalog: catalog, snapshot: snapshot(), tier: nil))
        let rarePlus: Set<Int> = [1, 3, 6, 7, 8, 9, 11, 12]
        XCTAssertFalse(HatchPlanner.hasCandidates(catalog: catalog, snapshot: snapshot(graduated: rarePlus), tier: .rare))
        XCTAssertTrue(HatchPlanner.hasCandidates(catalog: catalog, snapshot: snapshot(graduated: rarePlus), tier: .uncommon))
        XCTAssertFalse(HatchPlanner.hasCandidates(catalog: catalog, snapshot: snapshot(graduated: allIDs), tier: nil))
    }

    func test_collectionSnapshotSplitsGraduatedFromReached() {
        var state = CompanionState()
        let id = { GunplaID.encode(machineID: $0, grade: $1) }
        // 2 graduated at PG, and also released once earlier at HG — graduated wins, no reached entry.
        state.dex.append(DexEntry(baseID: id(2, .sd), finalID: id(2, .hg), chainOrder: [id(2, .sd), id(2, .hg)],
                                  rarity: .common, caughtAt: nil, releasedAt: Date()))
        state.dex.append(DexEntry(baseID: id(2, .hg), finalID: id(2, .pg),
                                  chainOrder: [.hg, .rg, .mg, .pg].map { id(2, $0) },
                                  rarity: .common, caughtAt: nil))
        // 1 released twice — highest reached grade is kept.
        state.dex.append(DexEntry(baseID: id(1, .sd), finalID: id(1, .rg), chainOrder: [.sd, .hg, .rg].map { id(1, $0) },
                                  rarity: .rare, caughtAt: nil, releasedAt: Date()))
        state.dex.append(DexEntry(baseID: id(1, .sd), finalID: id(1, .hg), chainOrder: [id(1, .sd), id(1, .hg)],
                                  rarity: .rare, caughtAt: nil, releasedAt: Date()))
        // Active 4 has reached MG (stage 1 of hg→mg).
        state.active = MonState(baseID: id(4, .hg), pathIDs: [id(4, .hg), id(4, .mg)], stageIndex: 1,
                                usedAtStage: 0, rarity: .common, totalForms: 2)

        let snap = state.collectionSnapshot(catalog: catalog)
        XCTAssertEqual(snap.graduatedMachineIDs, [2])
        XCTAssertEqual(snap.highestReachedGrade, [1: .rg, 4: .mg])
    }
}
