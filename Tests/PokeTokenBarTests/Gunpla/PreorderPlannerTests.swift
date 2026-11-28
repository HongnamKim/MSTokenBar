import XCTest
@testable import PokeTokenBar

final class PreorderPlannerTests: XCTestCase {
    private let catalog = MachineCatalog.allBundled
    private let zaku = 2, charZaku = 3, gouf = 5

    private func snapshot(graduated: Set<Int> = [], owned: [Int: Set<GunplaGrade>] = [:]) -> CollectionSnapshot {
        var grades = owned
        for id in graduated { grades[id] = Set(catalog.machine(id: id)!.grades) }
        return CollectionSnapshot(graduatedMachineIDs: graduated, ownedGrades: grades)
    }
    private func choose(_ snap: CollectionSnapshot, tier: Rarity? = nil, series: String? = nil,
                        preorder: Preorder? = nil, sequence: [UInt64]) -> HatchChoice? {
        var rng: any RandomNumberGenerator = SequenceRNG(sequence)
        return HatchPlanner.choose(catalog: catalog, snapshot: snap, tier: tier, series: series,
                                   preorder: preorder, toolLevel: 0, rng: &rng)
    }
    private func machineID(_ choice: HatchChoice?) -> Int? {
        choice.flatMap { GunplaID.decode($0.startSpeciesID)?.machineID }
    }
    private func ids(in series: String, variants: Bool? = nil) -> Set<Int> {
        Set(catalog.machines.filter { m in m.series == series && (variants.map { v in m.isVariant == v } ?? true) }.map(\.id))
    }

    func test_fourthBoxIsTheTarget() {
        for sequence: [UInt64] in [[1, 2, 3], [0], [7, 7, 7]] {
            let choice = choose(snapshot(), preorder: Preorder(machineID: gouf, boxesOpened: 3), sequence: sequence)
            XCTAssertEqual(machineID(choice), gouf, "\(sequence)")
        }
    }

    func test_rollOfZeroModFourIsTheTarget() {
        for roll: UInt64 in [0, 4, 8, 400] {
            let choice = choose(snapshot(), preorder: Preorder(machineID: gouf, boxesOpened: 0), sequence: [roll, 1, 1])
            XCTAssertEqual(machineID(choice), gouf, "roll=\(roll)")
        }
    }

    /// A miss spends exactly one value; the box's own roll sees the rest of the stream.
    func test_missFallsBackToTheBoxsOwnRoll() {
        for miss: UInt64 in [1, 2, 3, 5] {
            for (a, b) in [(1, 0), (1, 77), (0, 3), (5, 12_345)] as [(UInt64, UInt64)] {
                let withPreorder = choose(snapshot(), preorder: Preorder(machineID: gouf, boxesOpened: 1),
                                          sequence: [miss, a, b])
                let without = choose(snapshot(), sequence: [a, b, miss])
                XCTAssertEqual(withPreorder, without, "miss=\(miss) a=\(a) b=\(b)")
            }
        }
    }

    func test_missCanStillBringTheTargetNaturally() {
        let everyOtherMachine = Set(catalog.machines.map(\.id)).subtracting([gouf])
        let choice = choose(snapshot(graduated: everyOtherMachine), preorder: Preorder(machineID: gouf, boxesOpened: 0),
                            sequence: [1, 1, 0])
        XCTAssertEqual(machineID(choice), gouf)
    }

    func test_hitRateIsAQuarter() {
        // A rare box cannot bring the uncommon Gouf on its own roll, so every hit is the pre-order's.
        var rng: any RandomNumberGenerator = SeededRNG(seed: 3)
        let trials = 20_000
        var hits = 0
        for _ in 0..<trials {
            let choice = HatchPlanner.choose(catalog: catalog, snapshot: snapshot(), tier: .rare,
                                             preorder: Preorder(machineID: gouf, boxesOpened: 0), toolLevel: 0, rng: &rng)
            if machineID(choice) == gouf { hits += 1 }
        }
        XCTAssertEqual(Double(hits) / Double(trials), 0.25, accuracy: 0.015)
    }

    func test_targetBelowTheBoxTierStillArrives() {
        let choice = choose(snapshot(), tier: .rare, preorder: Preorder(machineID: zaku, boxesOpened: 3), sequence: [1])
        XCTAssertEqual(machineID(choice), zaku)
    }

    func test_targetOutsideTheSeriesStillArrivesAndAMissStaysInTheSeries() {
        XCTAssertEqual(machineID(choose(snapshot(), series: "0080", preorder: Preorder(machineID: gouf, boxesOpened: 3),
                                        sequence: [1])), gouf)
        let miss = choose(snapshot(), series: "0080", preorder: Preorder(machineID: gouf, boxesOpened: 0),
                          sequence: [1, 1, 9])
        XCTAssertTrue(ids(in: "0080").contains(machineID(miss) ?? -1))
    }

    func test_targetStartsWhereABoxRunWould() throws {
        let snap = snapshot(owned: [gouf: [.sd]])
        let choice = try XCTUnwrap(choose(snap, preorder: Preorder(machineID: gouf, boxesOpened: 3), sequence: [1]))
        let machine = try XCTUnwrap(catalog.machine(id: gouf))
        XCTAssertEqual(choice.startSpeciesID, GunplaID.encode(machineID: gouf, grade: HatchPlanner.runGrades(machine, snapshot: snap)[0]))
        XCTAssertFalse(choice.isVariant)
        XCTAssertEqual(choose(snapshot(), preorder: Preorder(machineID: charZaku, boxesOpened: 3), sequence: [1])?.isVariant, true)
    }

    func test_seriesBoxOnlyOpensThatSeries() {
        var rng: any RandomNumberGenerator = SeededRNG(seed: 5)
        let zeta = ids(in: "zeta")
        for _ in 0..<2_000 {
            let choice = HatchPlanner.choose(catalog: catalog, snapshot: snapshot(), tier: nil, series: "zeta",
                                             toolLevel: 0, rng: &rng)
            XCTAssertTrue(zeta.contains(machineID(choice) ?? -1))
        }
    }

    func test_seriesWithoutCustomsFallsBackToBases() {
        XCTAssertTrue(ids(in: "0080", variants: true).isEmpty, "fixture: 0080 has no custom unit")
        for pick: UInt64 in [0, 7, 99] {
            let choice = choose(snapshot(), series: "0080", sequence: [0, pick])   // the variant roll hits
            XCTAssertEqual(choice?.isVariant, false)
            XCTAssertTrue(ids(in: "0080").contains(machineID(choice) ?? -1))
        }
    }

    func test_seriesWithOnlyCustomsLeftStillOpens() {
        let snap = snapshot(graduated: ids(in: "first", variants: false))
        for pick: UInt64 in [0, 7, 99] {
            let choice = choose(snap, series: "first", sequence: [1, pick])   // the variant roll misses
            XCTAssertEqual(choice?.isVariant, true)
            XCTAssertTrue(ids(in: "first", variants: true).contains(machineID(choice) ?? -1))
            XCTAssertEqual(choice?.isDuplicatePhase, false)
        }
    }

    func test_completedSeriesRepeatsWithinTheSeries() {
        var rng: any RandomNumberGenerator = SeededRNG(seed: 9)
        let snap = snapshot(graduated: ids(in: "0080"))
        for _ in 0..<200 {
            let choice = HatchPlanner.choose(catalog: catalog, snapshot: snap, tier: nil, series: "0080",
                                             toolLevel: 0, rng: &rng)
            XCTAssertTrue(ids(in: "0080").contains(machineID(choice) ?? -1))
            XCTAssertEqual(choice?.isDuplicatePhase, true)
        }
    }
}
