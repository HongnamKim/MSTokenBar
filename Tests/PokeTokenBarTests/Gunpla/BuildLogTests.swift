import XCTest
@testable import PokeTokenBar

final class BuildLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_086_400)
    private let sd = 100_010, hg = 100_012

    private func stage(_ id: Int, _ tokens: [String: Int] = [:], sandpaper: Int = 0, unattributed: Int = 0,
                       at: Date? = nil) -> BuildStage {
        BuildStage(speciesID: id, reachedAt: at, tokensByProvider: tokens, sandpaper: sandpaper,
                   unattributed: unattributed)
    }

    func test_openedStartsOneStageStampedWithTheOpenTime() {
        XCTAssertEqual(BuildLog.opened(speciesID: sd, at: t0),
                       BuildLog(openedAt: t0, stages: [stage(sd, at: t0)]))
    }

    func test_resumedHoldsTheBankedAmountAsUnattributedWithNoTimes() {
        XCTAssertEqual(BuildLog.resumed(speciesID: hg, banked: 500),
                       BuildLog(openedAt: nil, stages: [stage(hg, unattributed: 500)]))
    }

    func test_addAccumulatesEachSourceInItsOwnBucket() {
        var log = BuildLog.opened(speciesID: sd, at: t0)
        log.add(.providers(["a": 100, "b": 40, "zero": 0]), to: sd)
        log.add(.providers(["a": 5]), to: sd)
        log.add(.sandpaper(7), to: sd)
        log.add(.unattributed(3), to: sd)
        XCTAssertEqual(log.stages, [stage(sd, ["a": 105, "b": 40], sandpaper: 7, unattributed: 3, at: t0)])
        XCTAssertEqual(BuildIncrement.providers(["a": 100, "b": 40]).total, 140)
        XCTAssertEqual(BuildIncrement.sandpaper(7).total, 7)
        XCTAssertEqual(BuildIncrement.unattributed(3).total, 3)
    }

    func test_addCreatesTheStageWhenItIsMissing() {
        var log = BuildLog.opened(speciesID: sd, at: t0)
        log.add(.providers(["a": 1]), to: hg)
        XCTAssertEqual(log.stages, [stage(sd, at: t0), stage(hg, ["a": 1])])
    }

    /// The spec's example: threshold 1,000, banked 1,200, so one sixth of every bucket moves on.
    func test_advanceMovesTheOverflowShareAndStampsTheNewGrade() {
        var log = BuildLog(openedAt: t0, stages: [stage(sd, ["claude": 900, "codex": 300], at: t0)])
        log.advance(from: sd, to: hg, banked: 1_200, threshold: 1_000, at: t1)
        XCTAssertEqual(log.stages, [stage(sd, ["claude": 750, "codex": 250], at: t0),
                                    stage(hg, ["claude": 150, "codex": 50], at: t1)])
    }

    func test_advanceConservesEveryBucketWhenTheShareDoesNotDivide() {
        var log = BuildLog(openedAt: t0, stages: [
            stage(sd, ["claude": 100, "codex": 7], sandpaper: 3, unattributed: 1, at: t0)])
        log.advance(from: sd, to: hg, banked: 111, threshold: 100, at: t1)   // 11/111 moves, rounded down
        XCTAssertEqual(log.stages, [stage(sd, ["claude": 91, "codex": 7], sandpaper: 3, unattributed: 1, at: t0),
                                    stage(hg, ["claude": 9], at: t1)])
    }

    /// After a difficulty change the buckets no longer add up to the banked growth.
    func test_advanceUsesBankedGrowthNotTheBucketSum() {
        var log = BuildLog(openedAt: t0, stages: [stage(sd, ["claude": 560], at: t0)])
        log.advance(from: sd, to: hg, banked: 110, threshold: 100, at: t1)
        XCTAssertEqual(log.stages, [stage(sd, ["claude": 510], at: t0), stage(hg, ["claude": 50], at: t1)])
    }

    func test_advanceAtTheTokenCeilingDoesNotTrap() {
        let top = SaveTransfer.maxTokenValue
        var log = BuildLog(openedAt: nil, stages: [stage(sd, ["a": top], sandpaper: top, unattributed: top)])
        log.advance(from: sd, to: hg, banked: top, threshold: 1, at: t1)
        XCTAssertEqual(log.stages, [stage(sd, ["a": 1], sandpaper: 1, unattributed: 1),
                                    stage(hg, ["a": top - 1], sandpaper: top - 1, unattributed: top - 1, at: t1)])
    }

    func test_advanceWithNoOverflowOnlyOpensTheNewStage() {
        var log = BuildLog(openedAt: t0, stages: [stage(sd, ["a": 1_000], at: t0)])
        log.advance(from: sd, to: hg, banked: 1_000, threshold: 1_000, at: t1)
        XCTAssertEqual(log.stages, [stage(sd, ["a": 1_000], at: t0), stage(hg, at: t1)])
    }

    func test_advanceIntoAnExistingStageMergesAndKeepsItsReachedAt() {
        var log = BuildLog(openedAt: t0, stages: [stage(sd, ["a": 1_200], at: t0), stage(hg, ["a": 10], at: t0)])
        log.advance(from: sd, to: hg, banked: 1_200, threshold: 1_000, at: t1)
        XCTAssertEqual(log.stages, [stage(sd, ["a": 1_000], at: t0), stage(hg, ["a": 210], at: t0)])
    }

    func test_keepingDropsStagesOutsideTheChain() {
        let log = BuildLog(openedAt: t0, stages: [stage(sd, ["a": 1], at: t0), stage(hg, ["a": 2], at: t1)])
        XCTAssertEqual(log.keeping([sd]), BuildLog(openedAt: t0, stages: [stage(sd, ["a": 1], at: t0)]))
    }

    func test_clampedBoundsNegativeAndHugeNumbers() {
        let log = BuildLog(openedAt: nil, stages: [
            stage(sd, ["a": Int.max, "b": -5], sandpaper: Int.min, unattributed: Int.max)])
        let top = SaveTransfer.maxTokenValue
        XCTAssertEqual(log.clamped(to: top).stages,
                       [stage(sd, ["a": top, "b": 0], sandpaper: 0, unattributed: top)])
    }

    func test_recordSurvivesEncodeDecodeOnMonStateAndDexEntry() throws {
        let log = BuildLog(openedAt: t0, stages: [stage(sd, ["a": 1], sandpaper: 2, unattributed: 3, at: t0)])
        let mon = MonState(baseID: sd, pathIDs: [sd], stageIndex: 0, usedAtStage: 6, rarity: .rare,
                           totalForms: 1, buildLog: log)
        XCTAssertEqual(try JSONDecoder().decode(MonState.self, from: JSONEncoder().encode(mon)).buildLog, log)
        let entry = DexEntry(baseID: sd, finalID: sd, chainOrder: [sd], rarity: .rare, caughtAt: t1, buildLog: log)
        XCTAssertEqual(try JSONDecoder().decode(DexEntry.self, from: JSONEncoder().encode(entry)).buildLog, log)
    }

    private let monJSON = #"{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":9,"rarity":"common","totalForms":1"#
    private let entryJSON = #"{"baseID":1,"finalID":1,"chainOrder":[1],"rarity":"common""#

    func test_savesWithoutARecordDecodeAsNil() throws {
        XCTAssertNil(try JSONDecoder().decode(MonState.self, from: Data((monJSON + "}").utf8)).buildLog)
        XCTAssertNil(try JSONDecoder().decode(DexEntry.self, from: Data((entryJSON + "}").utf8)).buildLog)
    }

    func test_corruptRecordDecodesAsNilAndKeepsTheMachineAndTheHangarEntry() throws {
        let mon = try JSONDecoder().decode(MonState.self, from: Data((monJSON + #","buildLog":"garbage"}"#).utf8))
        XCTAssertNil(mon.buildLog)
        XCTAssertEqual(mon.usedAtStage, 9)
        let entry = try JSONDecoder().decode(
            DexEntry.self, from: Data((entryJSON + #","buildLog":{"stages":"x"}}"#).utf8))
        XCTAssertNil(entry.buildLog)
        XCTAssertEqual(entry.chainOrder, [1])
    }

    func test_addSaturatesInsteadOfTrappingWhenABucketOverflows() {
        var log = BuildLog(openedAt: t0, stages: [stage(sd, ["a": Int.max - 1], sandpaper: Int.max, unattributed: Int.max)])
        log.add(.providers(["a": 5]), to: sd)
        log.add(.sandpaper(1), to: sd)
        log.add(.unattributed(1), to: sd)
        XCTAssertEqual(log.stages, [stage(sd, ["a": Int.max], sandpaper: Int.max, unattributed: Int.max)])
    }

    func test_advanceFromAGradeWithNoStageMovesNothing() {
        var log = BuildLog(openedAt: t0, stages: [stage(sd, ["a": 100])])
        log.advance(from: 999, to: hg, banked: 100, threshold: 50, at: t1)
        XCTAssertEqual(log.stages, [stage(sd, ["a": 100]), stage(hg, at: t1)])
    }
}
