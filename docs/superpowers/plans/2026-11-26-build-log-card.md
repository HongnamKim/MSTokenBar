# Build Record Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each build's record as a per-grade table card on the machine detail page, and replace the Pokémon-era "release" wording with "build stopped".

**Architecture:** A pure `BuildRecordSummary` turns one hangar entry and its `BuildLog` into rows, totals and a duration. `BuildRecordCard` renders it and `PokemonDetailView` shows it for the selected build. `PopoverNavigation` remembers which build a build-log row opened, and `PopoverView` hands tool display names down to the card.

**Tech Stack:** Swift 6, SwiftUI, XCTest, SwiftPM, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-11-26-build-log-card-design.md` (Korean). It builds on `docs/superpowers/specs/2026-11-25-build-log-design.md`.

## Global Constraints

- Read-only feature. Do not change `BuildLog`, `BuildStage`, how records accumulate, or the save format. `test_recordWrittenByThisReleaseStillDecodes` stays untouched and green.
- The card must fit `PopoverMetrics.scrollContentWidth`: a wider child widens the whole popover. No text may be truncated; the header line may wrap.
- A grade's stage is looked up by ID and the first match wins. Never build `Dictionary(uniqueKeysWithValues:)` from `stages`.
- No branch on a tool ID literal (`CLAUDE.md`, provider extension rule). Tool IDs are resolved only through the names dictionary.
- No timer and no repeating animation for the card.
- Copy exists in Korean, English and Japanese through `t(ko, en, ja)`. Use the exact strings each task gives.
- `CLAUDE.md` test rules: no guard and no test for input that cannot occur in this codebase; inject the defect once to see each new test fail; for new branches in a `LOGIC_CORE` file look at `llvm-cov show --show-regions` for `^0`. A `^0` that remains is reported with its line, not covered by a guard-only test.
- Surgical changes: touch only the lines a step names. Comments and test names that say 놓아줌 stay as they are.
- Git: commit messages in English, Conventional Commits. `git add` with explicit paths only. Never `git stash`, `reset`, `restore`, `checkout --` or `clean`: the working tree holds the owner's uncommitted files (`docs/gunpla/ideas.md`, `docs/gunpla/non-uc-roster.md`, `error.log`) and they must stay exactly as they are. Do not push.
- The shell is zsh.

## Review Focus

1. A record that began mid-build (`openedAt == nil`): grades before the first stage show "—", the header names the first recorded grade, and the unattributed amount is called "기록 전". Tests: Task 1 `test_recordThatBeganMidBuild`, Task 2 `test_headerText` (mid-build line) and `test_breakdownText`.
2. A hand-edited save with the same grade ID twice in `stages`, or a stage for a grade that is not on the build's path. The first match is used, the foreign stage is ignored, nothing traps. Test: Task 1 `test_duplicateAndForeignStages`.
3. The same machine and grade built twice: a click on the older row's final grade opens the older build, and every other route opens the default one. Tests: Task 3.
4. The widest card: eight grades ("MGSD", "Ver.Ka", "MGEX"), amounts in the billions, long tool names, in each language. Test: Task 2 `test_cardFitsThePopoverWidth`.
5. A tool that is no longer registered, and a clock that moved backwards after the box was opened. The raw ID is shown, and the day count never goes below day 1. Tests: Task 1 `test_toolOrderAndUnregisteredTools`, `test_raisingBuildCountsDaysFromOne`.

## Setup (controller, before Task 1)

- [ ] `git switch -c feat/build-log-card` from `feat/build-log` (e284d9a). The step-1 work is not on `main` yet; this branch stacks on it.
- [ ] Commit the spec and this plan:

```bash
git add docs/superpowers/specs/2026-11-26-build-log-card-design.md docs/superpowers/plans/2026-11-26-build-log-card.md
git commit -m "docs(build-log): add the build record card design and plan"
```

- [ ] Baseline: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`. Expected: `Executed 1874 tests, with 23 tests skipped and 0 failures`.

---

### Task 1: Build record summary

**Files:**
- Create: `Sources/PokeTokenBar/Gunpla/BuildRecordSummary.swift`
- Modify: `Sources/PokeTokenBar/Core/CompanionStore.swift:312-328` (`activeDexEntry`)
- Modify: `scripts/test-gate.sh` (`LOGIC_CORE`)
- Test: `Tests/PokeTokenBarTests/Gunpla/BuildRecordSummaryTests.swift` (create), `Tests/PokeTokenBarTests/Gunpla/BuildLogStoreTests.swift` (add one test)

**Interfaces:**
- Consumes: `DexEntry` (`chainOrder`, `caughtAt`, `isReleased`, `buildLog`), `BuildLog` (`openedAt`, `stages`), `BuildStage` (`speciesID`, `reachedAt`, `tokensByProvider`, `sandpaper`, `unattributed`).
- Produces:

```swift
/// What the build record card shows for one build. Pure: no store, clock or localization.
struct BuildRecordSummary: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case provider(id: String, name: String)   // name = display name, or the id when the tool is not registered
        case sandpaper
        case unattributed
    }
    struct Amount: Equatable, Sendable { let source: Source; let value: Int }
    struct Row: Equatable, Sendable {
        let speciesID: Int
        let reachedAt: Date?
        let isRecorded: Bool      // false = the build has no stage for this grade
        let tokens: Int           // all tools together
        let sandpaper: Int
        let unattributed: Int
        let amounts: [Amount]     // display order, values > 0 only; empty when not recorded
        var total: Int { tokens + sandpaper + unattributed }
    }
    enum End: Equatable, Sendable { case raising, completed(Date?), stopped(Date?) }
    enum Duration: Equatable, Sendable { case sameDay, days(Int), dayNumber(Int) }

    let openedAt: Date?
    let firstRecordedSpeciesID: Int   // the grade the header names when openedAt is nil
    let end: End
    let rows: [Row]                   // one per entry.chainOrder element, in that order
    let totals: [Amount]              // whole build, display order, values > 0 only
    var total: Int { get }            // sum of row totals
    var largestRowTotal: Int { get }  // 0 when every row is 0

    /// nil = no card: the entry has no record, or none of its grades has a stage.
    init?(entry: DexEntry, isRaising: Bool, providerNames: [String: String])
    /// nil when the opening time is unknown, or the build ended at an unknown time.
    func duration(now: Date, calendar: Calendar) -> Duration?
}
```

Display order of `amounts` and `totals`: tools by value descending, then name ascending, then id ascending; then sandpaper; then unattributed.

- [ ] **Step 1: Write the failing tests**

`Tests/PokeTokenBarTests/Gunpla/BuildRecordSummaryTests.swift`:

```swift
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
```

Add to `BuildLogStoreTests` (it already has `store`, `seeded`, `use`, `log`, `sd`):

```swift
    // MARK: display

    func test_theRaisingEntryCarriesItsRecord() async throws {
        let s = try store(seed: seeded())
        await s.hatch(baseID: sd)
        use(s, ["a": 100])
        let entry = try XCTUnwrap(s.pokemonIndividuals(speciesID: sd).first)
        XCTAssertTrue(s.isActiveDexEntry(entry))
        XCTAssertEqual(entry.buildLog, try log(s))
        XCTAssertEqual(entry.buildLog?.stages.first?.tokensByProvider, ["a": 100])
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter "BuildRecordSummaryTests|BuildLogStoreTests" 2>&1 | tail -20`
Expected: the build fails with "cannot find 'BuildRecordSummary' in scope".

- [ ] **Step 3: Implement `BuildRecordSummary` in `Sources/PokeTokenBar/Gunpla/BuildRecordSummary.swift`**

Exactly the interface above. Notes that the signature and tests leave open:
- A row's stage is `log.stages.first { $0.speciesID == id }`.
- `end` is `.raising` when `isRaising`, else `.stopped(entry.caughtAt)` when `entry.isReleased`, else `.completed(entry.caughtAt)`.
- A day count is the difference between `calendar.startOfDay(for:)` of the two dates in days, never below 0. Raising: `.dayNumber(count + 1)`. Ended: `.sameDay` when 0, else `.days(count)`.
- Sums use plain `+`. Every stored amount is at most 10^15 (`SaveTransfer.sanitized`).

- [ ] **Step 4: Let the raising entry carry its record**

In `CompanionStore.activeDexEntry`, pass `buildLog: active.buildLog` as the last argument of the `DexEntry(...)` it builds. Nothing else in that property changes. The entry is synthesized for display and never saved.

- [ ] **Step 5: Add the new file to the coverage gate**

In `scripts/test-gate.sh`, add `"Sources/PokeTokenBar/Gunpla/BuildRecordSummary.swift"` to `LOGIC_CORE` on the line after `BuildLog.swift`.

- [ ] **Step 6: Run the tests to see them pass**

Run: `swift test --filter "BuildRecordSummaryTests|BuildLogStoreTests" 2>&1 | grep -E "Executed|error|failed" | tail -5`
Expected: `Executed 28 tests, with 0 failures` (7 new + 21 in `BuildLogStoreTests`).

- [ ] **Step 7: Prove the duplicate test guards the lookup**

Temporarily change the stage lookup from `first` to `last(where:)`, run `swift test --filter BuildRecordSummaryTests/test_duplicateAndForeignStages`, see it fail, and change the line back by hand.

- [ ] **Step 8: Check regions**

```bash
swift test --enable-code-coverage --filter "BuildRecordSummaryTests" >/dev/null 2>&1
PROF=$(find .build -name 'default.profdata' | head -1)
BIN=$(find .build -name 'PokeTokenBarPackageTests' -type f ! -path '*.dSYM/*' | head -1)
xcrun llvm-cov show "$BIN" -instr-profile="$PROF" Sources/PokeTokenBar/Gunpla/BuildRecordSummary.swift --show-regions | grep -n '\^0'
```

Expected: no output. If a `^0` remains, report the exact line in your report; do not add a guard-only test.

- [ ] **Step 9: Commit**

```bash
git add Sources/PokeTokenBar/Gunpla/BuildRecordSummary.swift Sources/PokeTokenBar/Core/CompanionStore.swift scripts/test-gate.sh Tests/PokeTokenBarTests/Gunpla/BuildRecordSummaryTests.swift Tests/PokeTokenBarTests/Gunpla/BuildLogStoreTests.swift
git commit -m "feat(gunpla): summarise a build record for display"
```

---

### Task 2: The card on the machine detail page

**Files:**
- Create: `Sources/PokeTokenBar/UI/BuildRecordCard.swift`
- Modify: `Sources/PokeTokenBar/Core/Localization.swift` (new keys directly after `catchLogTitle`, line 1113)
- Modify: `Sources/PokeTokenBar/UI/CompanionView.swift` (`CollectionView` properties near line 993 and its `PokemonDetailView(...)` call near 1043; `PokemonDetailView` init near 1753 and body near 1795; `private extension View` with `detailCard()` near 1948)
- Modify: `Sources/PokeTokenBar/UI/PopoverView.swift:181`
- Modify: `Sources/PokeTokenBar/Core/UsageStore.swift` (after `registeredProviders`, line 233)
- Test: `Tests/PokeTokenBarTests/BuildRecordCardTests.swift` (create)

**Interfaces:**
- Consumes: `BuildRecordSummary` from Task 1, exactly as declared there.
- Produces:

```swift
// Localization.swift — exact copy from the spec, section 5.7
func buildRecordOpened(_ date: String) -> String { t("개봉 \(date)", "Opened \(date)", "開封 \(date)") }
func buildRecordCompleted(_ date: String) -> String { t("완성 \(date)", "Completed \(date)", "完成 \(date)") }
func buildRecordStopped(_ date: String) -> String { t("중단 \(date)", "Stopped \(date)", "中断 \(date)") }
func buildRecordDays(_ n: Int) -> String { t("\(n)일", n == 1 ? "1 day" : "\(n) days", "\(n)日") }
var buildRecordSameDay: String { t("당일", "Same day", "当日") }
func buildRecordDayNumber(_ n: Int) -> String { t("\(n)일째", "Day \(n)", "\(n)日目") }
func buildRecordTotal(_ amount: String) -> String { t("총 \(amount)", "Total \(amount)", "合計 \(amount)") }
func buildRecordSoFar(_ amount: String) -> String { t("지금까지 \(amount)", "\(amount) so far", "これまで \(amount)") }
func buildRecordFromMid(_ grade: String) -> String { t("\(grade) 도중부터 기록", "Recorded from mid-\(grade)", "\(grade)の途中から記録") }
var buildRecordBeforeRecord: String { t("기록 전", "Before record", "記録前") }
var buildRecordBeforeUnboxing: String { t("개봉 전 사용분", "Before unboxing", "開封前") }

// BuildRecordCard.swift
@MainActor
struct BuildRecordCard: View {
    let summary: BuildRecordSummary
    let l: L
    let locale: Locale
    var now: Date = Date()
    var calendar: Calendar = .current

    /// A numeric date in `locale` and the calendar's time zone: with the year ("2026. 11. 27.") or month and day only.
    static func dateText(_ date: Date, year: Bool, locale: Locale, calendar: Calendar) -> String
    /// The line under the title (spec 5.4).
    static func headerText(_ summary: BuildRecordSummary, l: L, locale: Locale, now: Date, calendar: Calendar) -> String
    /// "Alpha 100 · 스펀지 사포 50": a grade's tooltip (spec 5.6). The footer uses the same names and order.
    static func breakdownText(_ amounts: [BuildRecordSummary.Amount], openedAtKnown: Bool, l: L) -> String
}

// UsageStore.swift
/// Tool id → the name Settings shows; what the build record card labels a tool with.
var providerDisplayNames: [String: String] { get }

// CompanionView.swift
// CollectionView gains:      var providerNames: [String: String] = [:]
// PokemonDetailView.init:    init(store:species:onBack:selectedShiny:providerNames:spriteStore:), providerNames defaults to [:]
// detailCard() becomes visible to the module (drop `private` from its extension).
```

Rules the code must follow (spec 5.2 to 5.6):
- `headerText` joins, with `" · "`: the opening part, the duration (omitted when `summary.duration(...)` is nil) and the total. The opening part is `buildRecordOpened(date)` or, when `openedAt` is nil, `buildRecordFromMid(grade label)`; when the build has ended at a known time it continues with `" → "` and `buildRecordCompleted(date)` or `buildRecordStopped(date)`. Header dates carry the year. The total is `buildRecordSoFar` while raising, else `buildRecordTotal`, with `TokenFormatter.compact`.
- A grade label is `GunplaID.decode(id)?.grade.label`.
- A source's name: the tool's `name`; `l.itemName(.rareCandy)` for sandpaper; for unattributed `buildRecordBeforeUnboxing` when the opening time is known, else `buildRecordBeforeRecord`.
- `breakdownText` is `"name amount"` items joined with `" · "`, amounts through `TokenFormatter.compact`.

Layout (the builder's call within these): wrap the card in `.detailCard()`. Title `l.catchLogTitle` in the style of `PokemonDetailView.detailTitle`, with `Badge(l.dexRaising.uppercased(), tint: .accent, style: .tinted, size: 10)` beside it while raising. The header is one wrapping `Text`. Rows are a four-column grid: grade (the last row in the accent colour while raising), date without the year ("—" when nil), bar, amount (trailing, "—" when the row is not recorded). Rows are identified by position, not by grade ID. A bar is as wide as `row.total / largestRowTotal` of its column and is split left to right into unattributed (`Color.secondary`), tokens (`Color.accentColor`) and sandpaper (`Color.orange`); a row that is not recorded, or a card whose `largestRowTotal` is 0, draws no bar. A row with amounts gets `.help(breakdownText(...))` and the same string as its accessibility value. The footer lists `summary.totals`, each with a dot in its segment colour, and must wrap onto further lines (concatenated `Text` values wrap; an `HStack` does not).

- [ ] **Step 1: Write the failing tests**

`Tests/PokeTokenBarTests/BuildRecordCardTests.swift`:

```swift
import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BuildRecordCardTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private func day(_ n: Int) -> Date { t0.addingTimeInterval(Double(n) * 86_400) }
    private func id(_ grade: GunplaGrade) -> Int { GunplaID.encode(machineID: 1, grade: grade) }

    /// One tool ("a") per grade. `recordedFrom` leaves the earlier grades without a stage; `tokens` then
    /// lists the recorded grades only, and `unattributed` goes to the first of them.
    private func build(_ grades: [GunplaGrade], _ tokens: [Int], openedAt: Date?, caughtAt: Date? = nil,
                       stopped: Bool = false, raising: Bool = false, recordedFrom: Int = 0,
                       unattributed: Int = 0) throws -> BuildRecordSummary {
        let chain = grades.map(id)
        let stages = tokens.enumerated().map { offset, amount in
            BuildStage(speciesID: chain[recordedFrom + offset],
                       reachedAt: offset == 0 && openedAt == nil ? nil : day(recordedFrom + offset),
                       tokensByProvider: ["a": amount], unattributed: offset == 0 ? unattributed : 0)
        }
        let entry = DexEntry(id: "e", baseID: chain[0], finalID: chain[chain.count - 1], chainOrder: chain,
                             rarity: .rare, caughtAt: caughtAt, releasedAt: stopped ? caughtAt : nil,
                             buildLog: BuildLog(openedAt: openedAt, stages: stages))
        return try XCTUnwrap(BuildRecordSummary(entry: entry, isRaising: raising, providerNames: ["a": "Alpha"]))
    }

    func test_copyTable() {
        func all(_ pick: (L) -> String) -> [String] { [L(.ko), L(.en), L(.ja)].map(pick) }
        XCTAssertEqual(all { $0.buildRecordOpened("D") }, ["개봉 D", "Opened D", "開封 D"])
        XCTAssertEqual(all { $0.buildRecordCompleted("D") }, ["완성 D", "Completed D", "完成 D"])
        XCTAssertEqual(all { $0.buildRecordStopped("D") }, ["중단 D", "Stopped D", "中断 D"])
        XCTAssertEqual(all { $0.buildRecordDays(3) }, ["3일", "3 days", "3日"])
        XCTAssertEqual(L(.en).buildRecordDays(1), "1 day")
        XCTAssertEqual(all { $0.buildRecordSameDay }, ["당일", "Same day", "当日"])
        XCTAssertEqual(all { $0.buildRecordDayNumber(6) }, ["6일째", "Day 6", "6日目"])
        XCTAssertEqual(all { $0.buildRecordTotal("X") }, ["총 X", "Total X", "合計 X"])
        XCTAssertEqual(all { $0.buildRecordSoFar("X") }, ["지금까지 X", "X so far", "これまで X"])
        XCTAssertEqual(all { $0.buildRecordFromMid("HG") }, ["HG 도중부터 기록", "Recorded from mid-HG", "HGの途中から記録"])
        XCTAssertEqual(all { $0.buildRecordBeforeRecord }, ["기록 전", "Before record", "記録前"])
        XCTAssertEqual(all { $0.buildRecordBeforeUnboxing }, ["개봉 전 사용분", "Before unboxing", "開封前"])
    }

    func test_headerText() throws {
        let completed = try build([.sd, .mgsd, .hg, .rg, .mg],
                                  [142_900_000, 285_700_000, 428_600_000, 571_400_000, 982_100_000],
                                  openedAt: t0, caughtAt: day(17))
        let raising = try build([.sd, .mgsd, .hg], [142_900_000, 285_700_000, 91_300_000], openedAt: t0, raising: true)
        let stopped = try build([.sd, .mgsd], [142_900_000, 167_300_000], openedAt: t0, caughtAt: day(6), stopped: true)
        let midBuild = try build([.sd, .mgsd, .hg, .rg], [248_600_000, 571_400_000], openedAt: nil, caughtAt: day(20),
                                 recordedFrom: 2, unattributed: 180_000_000)

        func date(_ d: Date, _ language: AppLanguage) -> String {
            BuildRecordCard.dateText(d, year: true, locale: language.displayLocale, calendar: utc)
        }
        func header(_ s: BuildRecordSummary, _ language: AppLanguage, now: Date) -> String {
            BuildRecordCard.headerText(s, l: L(language), locale: language.displayLocale, now: now, calendar: utc)
        }
        XCTAssertEqual(header(completed, .ko, now: day(30)), "개봉 \(date(t0, .ko)) → 완성 \(date(day(17), .ko)) · 17일 · 총 2.41B")
        XCTAssertEqual(header(raising, .ko, now: day(5)), "개봉 \(date(t0, .ko)) · 6일째 · 지금까지 519.9M")
        XCTAssertEqual(header(stopped, .ko, now: day(30)), "개봉 \(date(t0, .ko)) → 중단 \(date(day(6), .ko)) · 6일 · 총 310.2M")
        XCTAssertEqual(header(midBuild, .ko, now: day(30)), "HG 도중부터 기록 → 완성 \(date(day(20), .ko)) · 총 1B")
        XCTAssertEqual(header(completed, .en, now: day(30)), "Opened \(date(t0, .en)) → Completed \(date(day(17), .en)) · 17 days · Total 2.41B")
        XCTAssertEqual(header(completed, .ja, now: day(30)), "開封 \(date(t0, .ja)) → 完成 \(date(day(17), .ja)) · 17日 · 合計 2.41B")
        XCTAssertNotEqual(date(t0, .ko), BuildRecordCard.dateText(t0, year: false, locale: AppLanguage.ko.displayLocale, calendar: utc),
                          "rows drop the year")
    }

    func test_breakdownText() {
        let amounts = [BuildRecordSummary.Amount(source: .provider(id: "a", name: "Alpha"), value: 100),
                       BuildRecordSummary.Amount(source: .sandpaper, value: 100_000_000),
                       BuildRecordSummary.Amount(source: .unattributed, value: 7)]
        XCTAssertEqual(BuildRecordCard.breakdownText(amounts, openedAtKnown: true, l: L(.ko)),
                       "Alpha 100 · 스펀지 사포 100M · 개봉 전 사용분 7")
        XCTAssertEqual(BuildRecordCard.breakdownText(amounts, openedAtKnown: false, l: L(.ko)),
                       "Alpha 100 · 스펀지 사포 100M · 기록 전 7")
    }

    /// A child wider than the scroll content width widens the whole popover.
    func test_cardFitsThePopoverWidth() throws {
        let chain = GunplaGrade.allCases.map(id)   // all eight grades, with the widest labels
        let stages = chain.enumerated().map { offset, species in
            BuildStage(speciesID: species, reachedAt: day(offset * 40),
                       tokensByProvider: ["claude": 12_345_678_901, "codex": 9_876_543_210, "gemini": 1_234_567_890],
                       sandpaper: 300_000_000, unattributed: 123_456_789)
        }
        let entry = DexEntry(id: "wide", baseID: chain[0], finalID: chain[7], chainOrder: chain, rarity: .legendary,
                             caughtAt: day(400), buildLog: BuildLog(openedAt: t0, stages: stages))
        let names = ["claude": "Claude Code", "codex": "Codex", "gemini": "Antigravity (Gemini and 3P models)"]
        let wide = try XCTUnwrap(BuildRecordSummary(entry: entry, isRaising: false, providerNames: names))
        let width = PopoverMetrics.scrollContentWidth
        for language in AppLanguage.allCases {
            let controller = NSHostingController(rootView: BuildRecordCard(
                summary: wide, l: L(language), locale: language.displayLocale, now: day(400), calendar: utc))
            let size = controller.sizeThatFits(in: CGSize(width: width, height: 10_000))
            XCTAssertLessThanOrEqual(size.width, width + 0.5, "\(language)")
        }
    }
}
```

Add one more test to the same file, described here rather than spelled out because it mirrors `IndividualPickerRenderingTests` (read that file first and reuse its mounting code):

`test_detailPageShowsTheCardOnlyForABuildWithARecord`: build a save in Korean with one completed `DexEntry` for machine 1 whose `chainOrder` is `MachineCatalog.allBundled.machine(id: 1)!.grades` encoded with `GunplaID.encode`, once with `buildLog: nil` and once with a record that has a stage for every grade. Mount `PokemonDetailView(store:species:onBack:providerNames:spriteStore:)` at `PopoverMetrics.contentWidth` by 520 for each, find the first `NSScrollView` among the host's descendants and read `documentView.frame.height`. Assert the height with the record is at least 60 points more than without. When the environment variable `PTB_BUILD_RECORD_RENDER_DIR` names a directory, also write PNGs there: `detail-without-record.png` and `detail-with-record.png` (the whole page; use a taller mount for the capture if 520 cuts the card), and the card alone for the `raising`, `stopped` and `midBuild` fixtures of `test_headerText` as `card-raising.png`, `card-stopped.png`, `card-mid-build.png`. Use a throwaway `SpriteStore(directory:)`, never the real sprite cache.

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter BuildRecordCardTests 2>&1 | tail -20`
Expected: the build fails with "cannot find 'BuildRecordCard' in scope" and "has no member 'buildRecordOpened'".

- [ ] **Step 3: Add the copy to `Localization.swift`**

The eleven keys from the Interfaces block, directly after `catchLogTitle`, under a `// 제작 기록 카드 (기체 상세 화면)` comment.

- [ ] **Step 4: Implement `BuildRecordCard` in `Sources/PokeTokenBar/UI/BuildRecordCard.swift`**

The three static functions and the view, following the rules and the layout paragraph above. `dateText` sets the format style's `locale`, `calendar` and `timeZone` (from `calendar.timeZone`); the form with the year is `Date.FormatStyle(date: .numeric, time: .omitted)`, the same style the individual picker uses.

- [ ] **Step 5: Hand tool names down and place the card**

- `UsageStore.providerDisplayNames`: built from `providers` by assigning `id → displayName` into a dictionary (no `uniqueKeysWithValues`).
- `PopoverView`: `CollectionView(store: companion, navigation: nav, providerNames: store.providerDisplayNames)`.
- `CollectionView`: the new `providerNames` property, passed to `PokemonDetailView`.
- `PokemonDetailView`: the new init parameter and stored property. In `body`, between the `individuals.isEmpty` text and the profile section:

```swift
if let individual,
   let summary = BuildRecordSummary(entry: individual, isRaising: store.isActiveDexEntry(individual),
                                    providerNames: providerNames) {
    BuildRecordCard(summary: summary, l: store.l, locale: store.language.displayLocale)
}
```

- Drop `private` from the `extension View` that declares `detailCard()`.

- [ ] **Step 6: Run the tests to see them pass**

Run: `swift test --filter "BuildRecordCardTests|IndividualPickerRenderingTests|GunplaCopyTests" 2>&1 | grep -E "Executed|error|failed" | tail -5`
Expected: all pass, 0 failures.

- [ ] **Step 7: Prove the width test can fail**

Temporarily add `.frame(minWidth: 400)` to the card's root view, run `swift test --filter BuildRecordCardTests/test_cardFitsThePopoverWidth`, see it fail, and remove the line by hand. If the injected width does not make it fail, the measurement is wrong: stop and report BLOCKED instead of keeping a test that cannot fail.

- [ ] **Step 8: Render and look at the card**

```bash
mkdir -p .superpowers/sdd/2026-11-26-build-log-card/pr-images/card
PTB_BUILD_RECORD_RENDER_DIR="$PWD/.superpowers/sdd/2026-11-26-build-log-card/pr-images/card" swift test --filter BuildRecordCardTests/test_detailPageShowsTheCardOnlyForABuildWithARecord
```

Open the five PNGs with the Read tool and check: nothing is truncated, the header reads as in `test_headerText`, bars are proportional and coloured by source, the footer wraps instead of running off the card. Fix what is wrong before committing, and say in your report what you saw.

- [ ] **Step 9: Commit**

```bash
git add Sources/PokeTokenBar/UI/BuildRecordCard.swift Sources/PokeTokenBar/Core/Localization.swift Sources/PokeTokenBar/UI/CompanionView.swift Sources/PokeTokenBar/UI/PopoverView.swift Sources/PokeTokenBar/Core/UsageStore.swift Tests/PokeTokenBarTests/BuildRecordCardTests.swift
git commit -m "feat(hangar): show the build record on the machine detail page"
```

---

### Task 3: Open the build a build-log row was clicked on

**Files:**
- Modify: `Sources/PokeTokenBar/UI/PopoverView.swift:50-83` (`PopoverNavigation`)
- Modify: `Sources/PokeTokenBar/UI/CompanionView.swift` (`CollectionView.body` near 1043, `catchLog` near 1231, `PokemonDetailView.init` near 1753)
- Test: `Tests/PokeTokenBarTests/PopoverNavigationTests.swift` (add one test), `Tests/PokeTokenBarTests/BuildRecordNavigationTests.swift` (create)

**Interfaces:**
- Consumes: `PokemonDetailView.init(store:species:onBack:selectedShiny:providerNames:spriteStore:)` from Task 2.
- Produces:

```swift
// PopoverNavigation
/// The build (`DexEntry.id`) the open detail page starts on; nil = the page's default (raising, then newest).
/// Every plain write to `dexDetailCollectionID`, opening or closing, forgets it.
private(set) var dexDetailInstanceID: String?
/// A build-log row opens its own build.
func openDexDetail(collectionID: String, instanceID: String)

// CollectionView
/// The build a log row's click should open: the row's own entry when the clicked sprite is its final grade.
static func detailInstance(for entry: DexEntry, opening collectionID: String, links: [Int: String]) -> String?

// PokemonDetailView.init gains `initialInstanceID: String = ""` (after `selectedShiny`), the initial value of `selectedInstanceID`.
```

- [ ] **Step 1: Write the failing tests**

Add to `PopoverNavigationTests`:

```swift
    /// A build-log row opens its own build; every other way of opening or leaving a detail page forgets it.
    func testOpenDexDetailRemembersTheBuildUntilThePageChanges() {
        let nav = PopoverNavigation()
        nav.tab = .collection
        nav.openDexDetail(collectionID: "25", instanceID: "entry-1")
        XCTAssertEqual(nav.dexDetailCollectionID, "25")
        XCTAssertEqual(nav.dexDetailInstanceID, "entry-1")

        nav.dexDetailCollectionID = "26"             // a hangar cell
        XCTAssertNil(nav.dexDetailInstanceID)

        nav.openDexDetail(collectionID: "25", instanceID: "entry-1")
        nav.openDexEntry(collectionID: "25")         // a Home sprite, the same page
        XCTAssertEqual(nav.dexDetailCollectionID, "25")
        XCTAssertNil(nav.dexDetailInstanceID)

        nav.openDexDetail(collectionID: "25", instanceID: "entry-1")
        nav.dexDetailCollectionID = nil              // Back
        XCTAssertNil(nav.dexDetailInstanceID)

        nav.openDexDetail(collectionID: "25", instanceID: "entry-1")
        nav.tab = .home                              // leaving the tab
        XCTAssertNil(nav.dexDetailCollectionID)
        XCTAssertNil(nav.dexDetailInstanceID)
    }
```

`Tests/PokeTokenBarTests/BuildRecordNavigationTests.swift`:

```swift
import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BuildRecordNavigationTests: XCTestCase {
    private let sd = GunplaID.encode(machineID: 1, grade: .sd), hg = GunplaID.encode(machineID: 1, grade: .hg)

    func testALogRowOpensItsBuildOnlyFromItsFinalGrade() {
        let entry = DexEntry(id: "old", baseID: sd, finalID: hg, chainOrder: [sd, hg], rarity: .common, caughtAt: nil)
        let links = [sd: "sd-page", hg: "hg-page"]
        XCTAssertEqual(CollectionView.detailInstance(for: entry, opening: "hg-page", links: links), "old")
        XCTAssertNil(CollectionView.detailInstance(for: entry, opening: "sd-page", links: links))
    }
}
```

Add a second test to that file, described here because it reuses the mounting code of `IndividualPickerRenderingTests` (two fixtures, `fixture-0` older and `fixture-1` newer, same machine and grade):

`testTheDetailPageStartsOnTheRequestedBuild`: mount `PokemonDetailView` twice, once with `initialInstanceID: "fixture-0"` and once without the argument, and read `titleOfSelectedItem` of the single `NSPopUpButton`. The individual picker labels builds newest first as `#1`, `#2`. Assert the title has the prefix `#2` with the argument and `#1` without it.

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter "PopoverNavigationTests|BuildRecordNavigationTests" 2>&1 | tail -20`
Expected: the build fails with "has no member 'openDexDetail'" and "has no member 'detailInstance'".

- [ ] **Step 3: Implement the navigation state in `PopoverNavigation`**

`dexDetailCollectionID` gets a `didSet` that sets `dexDetailInstanceID = nil`. `openDexDetail` sets the collection ID first and the instance ID last. No existing write site changes.

- [ ] **Step 4: Wire `CollectionView` and `PokemonDetailView`**

- `PokemonDetailView.init`: the `initialInstanceID` parameter becomes the initial value of the `selectedInstanceID` state. The existing `.task` that fills an empty selection stays.
- `CollectionView.body`: pass `initialInstanceID: nav.dexDetailInstanceID ?? ""`.
- `CollectionView.catchLog`: the row's closure keeps `logReturnAnchor = entry.id`, then calls `navigation.openDexDetail(collectionID:instanceID:)` when `detailInstance(for:opening:links:)` returns an ID (pass the `dexLinks` already in scope), else sets `navigation.dexDetailCollectionID` as today.

- [ ] **Step 5: Run the tests to see them pass**

Run: `swift test --filter "PopoverNavigationTests|BuildRecordNavigationTests|DexBackNavigationTests|IndividualPickerRenderingTests" 2>&1 | grep -E "Executed|error|failed" | tail -5`
Expected: all pass, 0 failures.

- [ ] **Step 6: Prove the navigation test guards the reset**

Temporarily remove the `didSet` body from `dexDetailCollectionID`, run `swift test --filter PopoverNavigationTests/testOpenDexDetailRemembersTheBuildUntilThePageChanges`, see it fail, and restore the line by hand.

- [ ] **Step 7: Commit**

```bash
git add Sources/PokeTokenBar/UI/PopoverView.swift Sources/PokeTokenBar/UI/CompanionView.swift Tests/PokeTokenBarTests/PopoverNavigationTests.swift Tests/PokeTokenBarTests/BuildRecordNavigationTests.swift
git commit -m "feat(hangar): open the build a build-log row was clicked on"
```

---

### Task 4: "Build stopped" wording

**Files:**
- Modify: `Sources/PokeTokenBar/Core/Localization.swift` (lines 1121, 1664, 1669, 1689, 1699, 1703-1706 before Task 2 shifted them by about 13)
- Modify: `Sources/PokeTokenBar/Core/KoreanParticle.swift` (remove `object`)
- Modify: `Tests/PokeTokenBarTests/Gunpla/GunplaCopyTests.swift`, `Tests/PokeTokenBarTests/KoreanParticleTests.swift`, `Tests/PokeTokenBarTests/PreciousCompanionGuardTests.swift:81`
- Create: `Tests/PokeTokenBarTests/StopWordingRenderTests.swift`

**Interfaces:**
- Consumes: nothing from the earlier tasks.
- Produces: no new names. `KoreanParticle.object` no longer exists.

New strings (spec section 7). Only the strings listed change; every other argument of each `t(...)` call stays.

| Key | Korean | English | Japanese |
|---|---|---|---|
| `dexReleased` | 제작 중단 | Build stopped | 製作中断 |
| `eggDescription` (nil or common) | 지금 기체 제작을 중단하고 새 건프라 박스로 다시 시작해요. | unchanged | unchanged |
| `eggDescription` (tier) | 지금 기체 제작을 중단하고 \(r) 이상이 확정으로 나오는 박스를 받아요. | unchanged | unchanged |
| `eggReleaseNote` | 제작을 중단한 기체도 격납고에 남고, 같은 확률로 다시 만날 수 있어요. 키운 진행도만 사라져요. | unchanged | unchanged |
| `eggConfirm` | \(monName) 제작을 중단하고 \(KoreanParticle.direction.attach(to: eggName)) 바꿀까요? | unchanged | unchanged |
| `freshEggShinyWarning` | 전용기예요! 정말 제작을 중단할까요? | unchanged | unchanged |
| `freshEggLegendaryWarning` | 전설 등급 기체예요! 정말 제작을 중단할까요? | unchanged | unchanged |
| `freshEggDiscardShiny` | 전용기 제작 중단 | unchanged | unchanged |
| `freshEggDiscardValuable` | 제작 중단 | unchanged | unchanged |

- [ ] **Step 1: Add the render test and capture the screens as they are now**

`Tests/PokeTokenBarTests/StopWordingRenderTests.swift`, written like `SulkRenderTests` (read its header): every test is skipped unless `PTB_STOP_WORDING_RENDER_DIR` names a directory, and writes one PNG there. Use a Korean save in a temporary file and mount the view the way `DexBackNavigationTests.host` does.
- `test_buildLogList`: one `DexEntry` for machine 1 with `releasedAt` and `caughtAt` set; `navigation.showingCollectionLog = true`; mount `CollectionView(store:navigation:)` at `PopoverMetrics.contentWidth` by 520; write `build-log-list.png`.
- `test_shopBoxCard`: a save with an `active` machine, so the box card shows its second line; mount `ShopView(store:nav:)` at the same size; write `shop-box-card.png`.

```bash
mkdir -p .superpowers/sdd/2026-11-26-build-log-card/pr-images/before
PTB_STOP_WORDING_RENDER_DIR="$PWD/.superpowers/sdd/2026-11-26-build-log-card/pr-images/before" swift test --filter StopWordingRenderTests
```

Open both PNGs with the Read tool. Expected: the list row shows the badge 놓아줌 and the shop card says 놓아주고 and 놓아준 기체도.

- [ ] **Step 2: Write the failing tests**

In `GunplaCopyTests`, append `|놓아|逃が` to the `forbidden` pattern, and add:

```swift
    func test_stoppedBuildWording() {
        let ko = L(.ko)
        XCTAssertEqual([ko.dexReleased, L(.en).dexReleased, L(.ja).dexReleased], ["제작 중단", "Build stopped", "製作中断"])
        XCTAssertEqual(ko.eggDescription(nil), "지금 기체 제작을 중단하고 새 건프라 박스로 다시 시작해요.")
        XCTAssertEqual(ko.eggDescription(.rare), "지금 기체 제작을 중단하고 \(ko.rarityRare) 이상이 확정으로 나오는 박스를 받아요.")
        XCTAssertEqual(ko.eggReleaseNote, "제작을 중단한 기체도 격납고에 남고, 같은 확률로 다시 만날 수 있어요. 키운 진행도만 사라져요.")
        XCTAssertEqual(ko.eggConfirm("레트라", ko.eggName(.rare)), "레트라 제작을 중단하고 레어 박스로 바꿀까요?")
        XCTAssertEqual(ko.freshEggShinyWarning, "전용기예요! 정말 제작을 중단할까요?")
        XCTAssertEqual(ko.freshEggLegendaryWarning, "전설 등급 기체예요! 정말 제작을 중단할까요?")
        XCTAssertEqual(ko.freshEggDiscardShiny, "전용기 제작 중단")
        XCTAssertEqual(ko.freshEggDiscardValuable, "제작 중단")
        XCTAssertEqual(L(.en).freshEggDiscardValuable, "Send off")
        XCTAssertEqual(L(.ja).freshEggDiscardValuable, "手放す")
    }
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `swift test --filter GunplaCopyTests 2>&1 | grep -E "error|failed|line [0-9]+:" | head -30`
Expected: `test_stoppedBuildWording` fails, and `test_noPokemonWordsInLocalizationSourceLiterals` lists the literals that still say 놓아 or 逃が (ten literals on nine lines of `Localization.swift`).

- [ ] **Step 4: Change the copy**

Apply the table to `Localization.swift`.

- [ ] **Step 5: Remove `KoreanParticle.object` and update the two older tests**

- `KoreanParticle.swift`: delete `case object` and its two `switch` arms.
- `KoreanParticleTests.swift`: delete `testObjectFollowsFinalConsonant` and the `KoreanParticle.object` assertion in `testNonHangulEndingKeepsBothForms`; in `testKoreanCopyUsesTheMatchingParticle` the `eggConfirm` expectation becomes `"레트라 제작을 중단하고 레어 박스로 바꿀까요?"`.
- `PreciousCompanionGuardTests.swift:81`: the expected value becomes `"제작 중단"`.

- [ ] **Step 6: Run the tests to see them pass**

Run: `swift test --filter "GunplaCopyTests|KoreanParticleTests|PreciousCompanionGuardTests|LocalizationInterpolationTests" 2>&1 | grep -E "Executed|error|failed" | tail -5`
Expected: all pass, 0 failures.

Then: `grep -n '놓아\|逃が' Sources/PokeTokenBar/Core/Localization.swift`
Expected: comment lines only (lines starting with `//`).

- [ ] **Step 7: Capture the screens with the new wording**

```bash
mkdir -p .superpowers/sdd/2026-11-26-build-log-card/pr-images/after
PTB_STOP_WORDING_RENDER_DIR="$PWD/.superpowers/sdd/2026-11-26-build-log-card/pr-images/after" swift test --filter StopWordingRenderTests
```

Open both PNGs. Expected: the badge reads 제작 중단 and the shop card says 제작을 중단하고 and 제작을 중단한 기체도; no line is truncated by the longer wording.

- [ ] **Step 8: Commit**

```bash
git add Sources/PokeTokenBar/Core/Localization.swift Sources/PokeTokenBar/Core/KoreanParticle.swift Tests/PokeTokenBarTests/Gunpla/GunplaCopyTests.swift Tests/PokeTokenBarTests/KoreanParticleTests.swift Tests/PokeTokenBarTests/PreciousCompanionGuardTests.swift Tests/PokeTokenBarTests/StopWordingRenderTests.swift
git commit -m "fix(copy): say a build was stopped instead of released"
```

---

## After the tasks (controller)

- [ ] `./scripts/test-gate.sh`: exit 0. Record the `Executed N tests` line and the logic-core coverage.
- [ ] Region check for `Sources/PokeTokenBar/Gunpla/BuildRecordSummary.swift` as in Task 1 Step 8, on the full-suite profile.
- [ ] Re-render the card images on the final commit (Task 2 Step 8 command) so the PR shows the final wording.
- [ ] Real app: build and launch against a scratch state folder (`PTB_STATE_DIR`), never the owner's real save, with a save that has a machine being raised; open Home, click the machine, and look for the card. If the popover cannot be driven from here, say so plainly in the final report instead of claiming it was checked.
- [ ] The confirm dialog and the two warnings also change wording but only appear after a click. The PR needs an image for them: render or draw one and label it as such (`CLAUDE.md`, PR rules).
