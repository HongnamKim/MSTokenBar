import XCTest
@testable import PokeTokenBar

final class BuildRecordSummaryTests: XCTestCase {
    private typealias Amount = BuildRecordSummary.Amount
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 22:13:20 UTC
    private let names = ["a": "Alpha", "b": "Beta"]
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private func day(_ n: Int) -> Date { t0.addingTimeInterval(Double(n) * 86_400) }
    private func id(_ grade: GunplaGrade) -> Int { GunplaID.encode(machineID: 1, grade: grade) }
    private func tool(_ id: String, _ name: String, _ value: Int) -> Amount {
        Amount(source: .provider(id: id, name: name), value: value)
    }
    private func entry(_ grades: [GunplaGrade], log: BuildLog?, caughtAt: Date? = nil,
                       releasedAt: Date? = nil) -> DexEntry {
        let chain = grades.map(id)
        return DexEntry(id: "e", baseID: chain[0], finalID: chain[chain.count - 1], chainOrder: chain,
                        rarity: .rare, caughtAt: caughtAt, releasedAt: releasedAt, buildLog: log)
    }
    private func summary(_ entry: DexEntry, raising: Bool = false) -> BuildRecordSummary? {
        BuildRecordSummary(entry: entry, isRaising: raising, providerNames: names)
    }

    func test_completedBuild() throws {
        let log = BuildLog(openedAt: t0, stages: [
            BuildStage(speciesID: id(.sd), reachedAt: t0, tokensByProvider: ["a": 100, "b": 40]),
            BuildStage(speciesID: id(.mgsd), reachedAt: day(1), tokensByProvider: ["a": 200], sandpaper: 50),
            BuildStage(speciesID: id(.hg), reachedAt: day(3), tokensByProvider: ["b": 300]),
        ])
        let s = try XCTUnwrap(summary(entry([.sd, .mgsd, .hg], log: log, caughtAt: day(5))))
        XCTAssertEqual(s.rows.map(\.speciesID), [id(.sd), id(.mgsd), id(.hg)])
        XCTAssertEqual(s.rows.map(\.reachedAt), [t0, day(1), day(3)])
        XCTAssertEqual(s.rows.map(\.total), [140, 250, 300])
        XCTAssertEqual([s.rows[1].tokens, s.rows[1].sandpaper, s.rows[1].unattributed], [200, 50, 0])
        XCTAssertEqual(s.rows[0].amounts, [tool("a", "Alpha", 100), tool("b", "Beta", 40)])
        XCTAssertEqual(s.rows[1].amounts, [tool("a", "Alpha", 200), Amount(source: .sandpaper, value: 50)])
        XCTAssertEqual(s.totals, [tool("b", "Beta", 340), tool("a", "Alpha", 300), Amount(source: .sandpaper, value: 50)])
        XCTAssertEqual(s.total, 690)
        XCTAssertEqual(s.largestRowTotal, 300)
        XCTAssertEqual(s.openedAt, t0)
        XCTAssertEqual(s.firstRecordedSpeciesID, id(.sd))
        XCTAssertEqual(s.end, .completed(day(5)))
        XCTAssertEqual(s.duration(now: day(9), calendar: utc), .days(5))
    }

    func test_raisingBuildCountsDaysFromOne() throws {
        let log = BuildLog(openedAt: t0, stages: [BuildStage(speciesID: id(.sd), reachedAt: t0, tokensByProvider: ["a": 7])])
        let s = try XCTUnwrap(summary(entry([.sd], log: log), raising: true))
        XCTAssertEqual(s.end, .raising)
        XCTAssertEqual(s.duration(now: t0, calendar: utc), .dayNumber(1))
        XCTAssertEqual(s.duration(now: day(5), calendar: utc), .dayNumber(6))
        XCTAssertEqual(s.duration(now: day(-2), calendar: utc), .dayNumber(1), "a clock that moved back never counts below day 1")
    }

    func test_stoppedBuildOnTheSameDay() throws {
        let stopped = t0.addingTimeInterval(3_600)   // 23:13 UTC, the same calendar day
        let s = try XCTUnwrap(summary(entry([.sd], log: .opened(speciesID: id(.sd), at: t0),
                                            caughtAt: stopped, releasedAt: stopped)))
        XCTAssertEqual(s.end, .stopped(stopped))
        XCTAssertEqual(s.duration(now: day(9), calendar: utc), .sameDay)
        XCTAssertTrue(s.rows[0].isRecorded)
        XCTAssertEqual(s.total, 0)
        XCTAssertEqual(s.largestRowTotal, 0)
        XCTAssertEqual(s.totals, [])
    }

    func test_recordThatBeganMidBuild() throws {
        let log = BuildLog(openedAt: nil, stages: [
            BuildStage(speciesID: id(.hg), reachedAt: nil, tokensByProvider: ["a": 248], unattributed: 180),
            BuildStage(speciesID: id(.rg), reachedAt: day(8), tokensByProvider: ["a": 571]),
        ])
        let s = try XCTUnwrap(summary(entry([.sd, .mgsd, .hg, .rg], log: log, caughtAt: day(20))))
        XCTAssertEqual(s.rows.map(\.isRecorded), [false, false, true, true])
        XCTAssertEqual(s.rows.map(\.total), [0, 0, 428, 571])
        XCTAssertEqual(s.rows[0].amounts, [])
        XCTAssertNil(s.rows[2].reachedAt)
        XCTAssertEqual(s.rows[2].amounts, [tool("a", "Alpha", 248), Amount(source: .unattributed, value: 180)])
        XCTAssertNil(s.openedAt)
        XCTAssertEqual(s.firstRecordedSpeciesID, id(.hg))
        XCTAssertEqual(s.totals, [tool("a", "Alpha", 819), Amount(source: .unattributed, value: 180)])
        XCTAssertNil(s.duration(now: day(30), calendar: utc))
    }

    func test_duplicateAndForeignStages() throws {
        let log = BuildLog(openedAt: t0, stages: [
            BuildStage(speciesID: id(.sd), reachedAt: t0, tokensByProvider: ["a": 1]),
            BuildStage(speciesID: id(.sd), reachedAt: day(1), tokensByProvider: ["a": 99]),   // the same grade twice
            BuildStage(speciesID: id(.mg), reachedAt: day(2), tokensByProvider: ["a": 7]),    // not on this build's path
            BuildStage(speciesID: id(.hg), reachedAt: day(3), tokensByProvider: ["a": 2]),
        ])
        let s = try XCTUnwrap(summary(entry([.sd, .hg], log: log, caughtAt: day(4))))
        XCTAssertEqual(s.rows.map(\.total), [1, 2])
        XCTAssertEqual(s.rows[0].reachedAt, t0)
        XCTAssertEqual(s.total, 3)
        XCTAssertEqual(s.totals, [tool("a", "Alpha", 3)])
    }

    func test_noCardWithoutARecord() {
        XCTAssertNil(summary(entry([.sd, .hg], log: nil)))
        let foreign = BuildLog(openedAt: t0, stages: [BuildStage(speciesID: id(.mg), reachedAt: t0, tokensByProvider: ["a": 7])])
        XCTAssertNil(summary(entry([.sd, .hg], log: foreign)))
    }

    func test_toolOrderAndUnregisteredTools() throws {
        let log = BuildLog(openedAt: t0, stages: [
            BuildStage(speciesID: id(.sd), reachedAt: t0, tokensByProvider: ["zeta": 5, "a": 5, "b": 9],
                       sandpaper: 20, unattributed: 30),
        ])
        let s = try XCTUnwrap(summary(entry([.sd], log: log, caughtAt: day(1))))
        XCTAssertEqual(s.totals, [
            tool("b", "Beta", 9), tool("a", "Alpha", 5), tool("zeta", "zeta", 5),   // amount, then name; an unknown tool keeps its id
            Amount(source: .sandpaper, value: 20), Amount(source: .unattributed, value: 30),
        ])
    }
}
