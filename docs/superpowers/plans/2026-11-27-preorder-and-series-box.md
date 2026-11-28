# Pre-order and Series Box Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two shop products for aiming at a wanted Mobile Suit: a pre-order (25% per box, guaranteed by the 4th box) and a series box (only one series' machines come out).

**Architecture:** The box roll stays in one pure function: `HatchPlanner.choose` gains a `series` filter and a `preorder` roll that runs first. The store persists `CompanionState.preorder` (across boxes) and `CompanionState.eggSeries` (one box), counts pre-order boxes only where a box really opens (`hatchCore`), and lets the pre-order target through the tier gate. The UI reuses existing screens: the series box opens a series list inside the Shop tab, and the pre-order opens the hangar in a second pick mode next to the display-pet pick.

**Tech Stack:** Swift 6, SwiftUI, XCTest, SwiftPM, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-11-27-preorder-and-series-box-design.md` (Korean). Section numbers below (§5.2 …) refer to it.

## Global Constraints

- Pre-order rule (§5.2): if `boxesOpened >= 3` the box is the target; otherwise one roll `rng.next() % 4 == 0` makes it the target; otherwise the box's own roll runs (and may still bring the target). Constants: `Preorder.missesBeforeGuarantee = 3`, `Preorder.oddsDenominator: UInt64 = 4`. The same rule for every box kind (kit, tier, series).
- The pre-order count changes only in `hatchCore`, next to `state.eggTier = nil`. A box whose machine is the target (forced or natural) ends the pre-order; any other opened box adds 1. Nothing else touches the count.
- Prices are base prices from `FreshEgg.price(guaranteeing:)` (1B / 2.5B / 4B / 8B) scaled by shop difficulty. Always read them through `CompanionStore.price(of: .egg(rarity))`; never charge or show `FreshEgg.price` directly.
- Save format: no schema bump. `preorder` and `eggSeries` are optional fields decoded with `lenientOptional`. `SaveTransfer.sanitized` is the only place that normalizes them, using `MachineCatalog.shared`.
- Popover rules: no `.sheet` / `.alert`; confirms are inline. Nothing may be wider than `PopoverMetrics.scrollContentWidth` inside the popover's scroll views (`PopoverMetrics.contentWidth` for fixed-height tab content such as the hangar). Long names truncate on one line; only the name part truncates.
- Copy: Korean, English and Japanese through `t(ko, en, ja)`, exactly as Task 3 gives it. Model-kit wording (open a box, build, stop building, arrive), none of the words in `GunplaCopyTests.forbidden`. Korean particles after runtime names go through `KoreanParticle`. No Hangul string literal in `Sources/PokeTokenBar/UI` (`LocalizedUILiteralTests`).
- Unchanged behaviour: the normal hangar (unbuilt 전용기 hidden, silhouettes at the first grade, "???" names, rarity/전용기 filters drop silhouettes), the display-pet pick, `ShopEntry` and `shopEntries`, the three existing boxes' prices and odds, existing copy (`eggReleaseNote` and other strings are not reworded).
- `CLAUDE.md` test rules: no guard and no test for input that cannot occur in this codebase; inject the defect once to watch each guard test fail; for new branches in `LOGIC_CORE` files look at `xcrun llvm-cov show … --show-regions` for `^0`. A `^0` that remains is reported with its line.
- Surgical changes: touch only what a step names. Two refactors are part of this plan and keep behaviour identical: `buyEgg`'s body moves into `restartBox` (Task 5), and `EggCard`'s confirm stages move into `ReplaceBoxConfirmRow` (Task 7).
- Git: work on `feat/preorder-series-box`. Commit messages in English, Conventional Commits, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `git add` with explicit paths only. Never `git stash`, `reset`, `restore`, `checkout --` or `clean`: the working tree holds the owner's uncommitted files (`docs/gunpla/ideas.md`, `docs/gunpla/expansion-roster.md`, `error.log`) and they stay exactly as they are. Do not push.
- Do not launch the app binary from the repo root: after a coverage build it rewrites the tracked `default.profraw`. If `git status` ever shows `default.profraw` modified, the one allowed repair is `git restore --source=HEAD --worktree -- default.profraw`.
- The shell is zsh.

## Decisions this plan makes (spec §10 left them to the builder)

1. `ShopEntry` is not extended. The two new cards render after the existing entries in `ShopView`, because their prices are not fixed and `shopEntries` tests pin the list exactly.
2. `HatchChoice` is unchanged. The tier gate decides "is this the pre-order target" by comparing machine IDs, which also covers a pre-roll saved before a restart.
3. The pre-order roll consumes one RNG value before the variant roll; a guaranteed box consumes none. A missed roll leaves the rest of the stream to the box's own roll.
4. The pre-order arrival copy replaces the prayer copy too (§5.3 says "the hatch notification uses pre-order copy" without exception). Prayers still move onto the machine.
5. The series box confirm says "{기체} 제작을 중단하고 {작품} 작품 박스로 바꿀까요?" instead of "작품 박스(0080)로": a closing parenthesis has no 받침, so `KoreanParticle` would print "(으)로".
6. The floating pet hover and the egg display name keep saying "건프라 박스" for a series box. Only the home badge names the series (§7.6).
7. In pick mode the hangar header count and the rarity tallies count the whole pick list (every catalog machine), so a rarity the player never built can still be filtered.
8. Pick mode labels a machine being built "제작 중" with a new string; the existing "키우는 중" badge (`dexRaising`) is not reworded.
9. The pre-order card and the hangar pre-order mark use `WorkshopIcon(.box)`. The mark sits at the sprite's bottom-leading corner.
10. The mode chooser and the confirm row are one panel overlaid at the bottom of the hangar content (`.overlay(alignment: .bottom)`), so the grid does not relayout.

## Review Focus

1. The popover is closed (or the user leaves the tab, or switches to the build log) in the middle of a pre-order pick. On the next open the hangar is in its normal mode, there is no banner, and nothing was charged. Test: Task 6 `testPreorderPickEndsWhenLeavingSwitchingOrReopening`.
2. Shop difficulty is not 1.0. The price charged is the scaled price the screen showed. Tests: Task 4 `test_buyPreorderChargesTheScaledPrice`, Task 5 `test_seriesBoxChargesTheScaledPrice`.
3. A series whose only unfinished machines are custom units. The variant roll misses, the box still opens a custom unit of that series instead of stalling. Test: Task 2 `test_seriesWithOnlyCustomsLeftStillOpens`.
4. The longest series name in the home series badge, in every language. The badge truncates and the header stays within the popover width. Test: Task 9 `test_seriesBadgeKeepsTheHeaderWidth`.
5. A save exported in the middle of a pre-order (with a pre-rolled box) and imported on another device. The pre-order, its count and the series box move with it. Test: Task 1 `test_importKeepsPreorderAndSeriesBox`.

## Setup (controller, before Task 1)

- [ ] `git switch -c feat/preorder-series-box` from `main`.
- [ ] Commit the spec and this plan:

```bash
git add docs/superpowers/specs/2026-11-27-preorder-and-series-box-design.md docs/superpowers/plans/2026-11-27-preorder-and-series-box.md
git commit -m "docs(gunpla): add the pre-order and series box design and plan"
```

- [ ] Baseline: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`. Expected: 0 failures. Record the count in the ledger.

---

### Task 1: Save fields

**Files:**
- Modify: `Sources/PokeTokenBar/Core/CompanionModel.swift` (new `Preorder` before `CompanionState`; `CompanionState` fields and `init(from:)`; `FreshEgg.shopTiers` comment)
- Modify: `Sources/PokeTokenBar/Core/SaveTransfer.swift` (`sanitized`; `rebasedForThisDevice` doc comment)
- Test: `Tests/PokeTokenBarTests/Gunpla/PreorderSaveTests.swift` (create)

**Interfaces:**
- Produces:

```swift
/// A pre-order (spec §5): the machine, and the boxes opened without it since the purchase.
struct Preorder: Codable, Sendable, Equatable {
    var machineID: Int
    var boxesOpened: Int
    static let missesBeforeGuarantee = 3
    static let oddsDenominator: UInt64 = 4
    /// The next box is the 4th: it brings the machine.
    var isGuaranteedNext: Bool { boxesOpened >= Self.missesBeforeGuarantee }
    /// 1...4 — which box of the pre-order the next box is.
    var boxNumber: Int { boxesOpened + 1 }
}

extension CompanionState {
    var preorder: Preorder?     // stored property; persists across boxes and builds
    var eggSeries: String?      // stored property; the series of the box being held, nil while building
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import PokeTokenBar

final class PreorderSaveTests: XCTestCase {
    private func decode(_ json: String) throws -> CompanionState {
        try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
    }
    private func building() -> MonState {
        let id = GunplaID.encode(machineID: 2, grade: .sd)
        return MonState(baseID: id, pathIDs: [id], plannedPathIDs: [id], stageIndex: 0, usedAtStage: 0,
                        rarity: .common, totalForms: 1)
    }

    func test_roundTrip() throws {
        var state = CompanionState()
        state.preorder = Preorder(machineID: 5, boxesOpened: 2)
        state.eggSeries = "0080"
        let decoded = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.preorder, Preorder(machineID: 5, boxesOpened: 2))
        XCTAssertEqual(decoded.eggSeries, "0080")
    }

    func test_oldSaveHasNeither() throws {
        let s = try decode(#"{"usedSinceInstall":7}"#)
        XCTAssertNil(s.preorder)
        XCTAssertNil(s.eggSeries)
    }

    func test_brokenValuesDecodeToNoneAndKeepTheRest() throws {
        let s = try decode(#"{"usedSinceInstall":7,"preorder":{"machineID":"x"},"eggSeries":12}"#)
        XCTAssertNil(s.preorder)
        XCTAssertNil(s.eggSeries)
        XCTAssertEqual(s.usedSinceInstall, 7)
    }

    func test_sanitizeClampsTheCount() {
        for (raw, expected) in [(-5, 0), (0, 0), (3, 3), (4, 3), (Int.max, 3)] {
            var s = CompanionState()
            s.preorder = Preorder(machineID: 5, boxesOpened: raw)
            XCTAssertEqual(SaveTransfer.sanitized(s).preorder?.boxesOpened, expected, "\(raw)")
        }
    }

    func test_sanitizeDropsAPreorderTheCatalogDoesNotKnow() {
        var s = CompanionState()
        s.preorder = Preorder(machineID: 9_999, boxesOpened: 1)
        XCTAssertNil(SaveTransfer.sanitized(s).preorder)
    }

    func test_sanitizeKeepsASeriesBoxOnlyWhileHeldAndKnown() {
        var held = CompanionState()
        held.eggSeries = "0080"
        XCTAssertEqual(SaveTransfer.sanitized(held).eggSeries, "0080")

        var unknown = CompanionState()
        unknown.eggSeries = "nope"
        XCTAssertNil(SaveTransfer.sanitized(unknown).eggSeries)

        var whileBuilding = CompanionState()
        whileBuilding.eggSeries = "0080"
        whileBuilding.active = building()
        XCTAssertNil(SaveTransfer.sanitized(whileBuilding).eggSeries)
    }

    func test_importKeepsPreorderAndSeriesBox() {
        var imported = CompanionState()
        imported.preorder = Preorder(machineID: 5, boxesOpened: 2)
        imported.eggSeries = "0080"
        imported.pendingHatchID = GunplaID.encode(machineID: 30, grade: .hg)
        let rebased = SaveTransfer.rebasedForThisDevice(SaveTransfer.sanitized(imported), current: CompanionState(),
                                                        todayTokensByProvider: ["a": 1], todayDate: "d",
                                                        hasUsageData: true)
        XCTAssertEqual(rebased.preorder, Preorder(machineID: 5, boxesOpened: 2))
        XCTAssertEqual(rebased.eggSeries, "0080")
        XCTAssertEqual(rebased.pendingHatchID, imported.pendingHatchID)
    }
}
```

- [ ] **Step 2: Run to see it fail.** `swift test --filter PreorderSaveTests`. Expected: build error, `Preorder` / `preorder` / `eggSeries` unknown.

- [ ] **Step 3: Implement.**
  - `Preorder` as in Interfaces, placed before `CompanionState` in `CompanionModel.swift`.
  - `CompanionState`: add `var preorder: Preorder?` and `var eggSeries: String?` next to `eggTier` / `pendingHatchID`, each with a one-line comment (pre-order spans boxes; series is egg-scoped like `eggTier`, consumed at hatch). In `init(from:)`: `preorder = c.lenientOptional(Preorder.self, forKey: .preorder)`, `eggSeries = c.lenientOptional(String.self, forKey: .eggSeries)`.
  - `SaveTransfer.sanitized`, after the existing `if s.active != nil { … }` line:
    - `if s.active != nil { s.eggSeries = nil }` (same reason as `eggTier`; add it to that existing line instead of a new `if` if it reads better)
    - `if let series = s.eggSeries, !MachineCatalog.shared.series.contains(where: { $0.id == series }) { s.eggSeries = nil }`
    - `if var preorder = s.preorder { … }`: drop it when `MachineCatalog.shared.machine(id:)` is nil, else clamp `boxesOpened` to `0...Preorder.missesBeforeGuarantee`.
    - One comment: unknown series would leave a box with no candidate that never opens; an unknown machine has no box to arrive in; the catalog is `.shared` like `FullArmorUnicornMigration` because `sanitized` takes no catalog.
  - `rebasedForThisDevice` doc comment: add `preorder`·`eggSeries` to the 진행 list.
  - `FreshEgg.shopTiers` comment: keep "등급 박스로는 레전더리를 팔지 않는다", and add that a specific legendary can be guaranteed through a pre-order or an 8B series box, by the owner's decision of 2026-11-27.

- [ ] **Step 4: Run.** `swift test --filter PreorderSaveTests`. Expected: all pass.

- [ ] **Step 5: Inject once.** Remove the `active != nil` clause for `eggSeries`, run, see `test_sanitizeKeepsASeriesBoxOnlyWhileHeldAndKnown` fail, restore.

- [ ] **Step 6: Commit.**

```bash
git add Sources/PokeTokenBar/Core/CompanionModel.swift Sources/PokeTokenBar/Core/SaveTransfer.swift Tests/PokeTokenBarTests/Gunpla/PreorderSaveTests.swift
git commit -m "feat(gunpla): persist pre-orders and series boxes in the save"
```

---

### Task 2: Box roll with series and pre-order

**Files:**
- Modify: `Sources/PokeTokenBar/Gunpla/HatchPlanner.swift` (`choose`, doc comments)
- Test: `Tests/PokeTokenBarTests/Gunpla/PreorderPlannerTests.swift` (create)

**Interfaces:**
- Consumes: `Preorder` (Task 1).
- Produces:

```swift
static func choose(catalog: MachineCatalog, snapshot: CollectionSnapshot, tier: Rarity?,
                   series: String? = nil, preorder: Preorder? = nil,
                   toolLevel: Int, rng: inout any RandomNumberGenerator) -> HatchChoice?
```

Existing call sites and tests compile unchanged (defaults sit between `tier` and `toolLevel`).

- [ ] **Step 1: Write the failing tests**

```swift
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
        Set(catalog.machines.filter { $0.series == series && (variants.map { v in $0.isVariant == v } ?? true) }.map(\.id))
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
```

- [ ] **Step 2: Run to see it fail.** `swift test --filter PreorderPlannerTests`. Expected: build error (extra arguments `series`, `preorder`).

- [ ] **Step 3: Implement** in `HatchPlanner.choose`:
  - First, before `eligible`:

```swift
if let preorder, let target = catalog.machine(id: preorder.machineID),
   preorder.isGuaranteedNext || rng.next() % Preorder.oddsDenominator == 0 {
    return choice(target, snapshot: snapshot, isDuplicatePhase: snapshot.isComplete(target))
}
```

  - `eligible` also keeps only `series == nil || $0.series == series`. Everything after it is unchanged.
  - Move the final `HatchChoice(...)` construction into `private static func choice(_ machine: MachineRecord, snapshot: CollectionSnapshot, isDuplicatePhase: Bool) -> HatchChoice` (start grade = `runGrades(machine, snapshot:)[0]`, `isVariant: machine.variantOf != nil`) and use it in both places.
  - Doc comment of `choose`: the pre-order roll comes first (§5.2) and the target passes any tier or series; `series` narrows the pool and keeps the duplicate phase inside the series.

- [ ] **Step 4: Run.** `swift test --filter "PreorderPlannerTests|HatchPlannerTests"`. Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/PokeTokenBar/Gunpla/HatchPlanner.swift Tests/PokeTokenBarTests/Gunpla/PreorderPlannerTests.swift
git commit -m "feat(gunpla): roll pre-orders and series boxes in the box planner"
```

---

### Task 3: Copy

**Files:**
- Modify: `Sources/PokeTokenBar/Core/Localization.swift` (new members next to the egg strings around line 1700, the notification pair next to `notifShinyHatchBody`)
- Test: `Tests/PokeTokenBarTests/Gunpla/GunplaCopyTests.swift` (`test_noPokemonWordsInVisibleCopy`), `Tests/PokeTokenBarTests/Gunpla/PreorderCopyTests.swift` (create)

**Interfaces:**
- Produces these `L` members, with exactly this copy:

| Member | ko | en | ja |
|---|---|---|---|
| `preorderTitle` | 예약 주문 | Pre-order | 予約注文 |
| `preorderDescription` | 원하는 기체를 골라 예약해요. 박스마다 25% 확률로 나오고, 늦어도 4번째 박스에서 받아요. | Pick a Mobile Suit to pre-order. Each box has a 25% chance to bring it, and the 4th box brings it at the latest. | 欲しい機体を選んで予約します。箱ごとに25%の確率で届き、遅くとも4箱目で受け取れます。 |
| `preorderPickPrompt` | 예약할 기체를 고르세요 | Pick a Mobile Suit to pre-order | 予約する機体を選んでください |
| `preorderOddsLine` | 박스마다 25% · 4번째 박스에 확정 | 25% per box · guaranteed by the 4th | 箱ごとに25%・4箱目で確定 |
| `preorderShort` (button and status prefix) | 예약 | Pre-order | 予約 |
| `preorderActiveLabel` | 예약 중 | Pre-ordered | 予約中 |
| `preorderBoxNumber(_ box: Int)` | \(box)/4번째 박스 | box \(box) of 4 | 4箱中\(box)箱目 |
| `preorderStatusOdds(box: Int, nextBox: Bool)` | 이번 박스 25% (\(box)/4) · 다음 박스 25% (\(box)/4) | This box 25% (\(box)/4) · Next box 25% (\(box)/4) | この箱 25% (\(box)/4) · 次の箱 25% (\(box)/4) |
| `preorderStatusGuaranteed(nextBox: Bool)` | 이번 박스에 확정 · 다음 박스에 확정 | Guaranteed this box · Guaranteed next box | この箱で確定 · 次の箱で確定 |
| `preorderNoCandidates` | 예약할 수 있는 기체가 없어요 | No Mobile Suit left to pre-order | 予約できる機体がありません |
| `preorderCompleteLabel` | 완성 | Complete | 完成 |
| `preorderBuildingLabel` | 제작 중 | Building | 製作中 |
| `notifPreorderTitle` | 예약 도착! | Pre-order arrived! | 予約到着！ |
| `notifPreorderBody(_ name: String)` | 예약한 \(KoreanParticle.subject.attach(to: name)) 도착했어요 | Your pre-ordered \(name) has arrived | 予約した\(name)が届きました |
| `seriesBoxTitle` | 작품 박스 | Series Box | 作品ボックス |
| `seriesBoxDescription` | 고른 작품의 기체만 나와요. | Only Mobile Suits from the series you pick come out. | 選んだ作品の機体だけが出ます。 |
| `seriesBoxConfirm(_ monName: String, _ seriesName: String)` | \(monName) 제작을 중단하고 \(seriesName) 작품 박스로 바꿀까요? | Stop building \(monName) and switch to a \(seriesName) Series Box? | \(monName)の製作を中止して\(seriesName)の作品ボックスにしますか？ |
| `seriesBoxRemaining(_ count: Int)` | 남은 \(count)기 | \(count) left | 残り\(count)機 |
| `seriesBoxHint(_ seriesName: String)` | 작품 · \(seriesName) | Series · \(seriesName) | 作品・\(seriesName) |
| `seriesBoxAllComplete` | 모든 작품을 완성했어요 | Every series is complete | すべての作品を完成しました |

In the two-form rows, the first form is `nextBox == false`, the second `nextBox == true`.

- [ ] **Step 1: Write the failing tests**
  - In `test_noPokemonWordsInVisibleCopy`, add every member above to `rendered` under a `// pre-order / series box` comment, calling the functions with `box: 2`, `nextBox: false` and `true`, names `"A"`, series `"Zeta"`, count `3`.
  - `PreorderCopyTests.swift`:

```swift
import XCTest
@testable import PokeTokenBar

final class PreorderCopyTests: XCTestCase {
    func test_arrivalPicksTheKoreanParticleAndNeverShowsOdds() {
        XCTAssertEqual(L(.ko).notifPreorderBody("구프"), "예약한 구프가 도착했어요")
        XCTAssertEqual(L(.ko).notifPreorderBody("건담 Mk-II(에우고)"), "예약한 건담 Mk-II(에우고)이(가) 도착했어요")
        for lang in AppLanguage.allCases { XCTAssertFalse(L(lang).notifPreorderBody("A").contains("1/")) }
    }

    func test_statusSaysThisBoxWhileHeldAndNextBoxWhileBuilding() {
        let l = L(.ko)
        XCTAssertEqual(l.preorderStatusOdds(box: 2, nextBox: false), "이번 박스 25% (2/4)")
        XCTAssertEqual(l.preorderStatusOdds(box: 2, nextBox: true), "다음 박스 25% (2/4)")
        XCTAssertEqual(l.preorderStatusGuaranteed(nextBox: false), "이번 박스에 확정")
        XCTAssertEqual(l.preorderStatusGuaranteed(nextBox: true), "다음 박스에 확정")
    }
}
```

- [ ] **Step 2: Run to see it fail.** `swift test --filter "GunplaCopyTests|PreorderCopyTests"`. Expected: build error, members unknown.
- [ ] **Step 3: Implement** the members with `t(ko, en, ja)`.
- [ ] **Step 4: Run.** Same filter plus `LocalizationInterpolationTests`. Expected: all pass.
- [ ] **Step 5: Commit.**

```bash
git add Sources/PokeTokenBar/Core/Localization.swift Tests/PokeTokenBarTests/Gunpla/GunplaCopyTests.swift Tests/PokeTokenBarTests/Gunpla/PreorderCopyTests.swift
git commit -m "feat(gunpla): add pre-order and series box copy"
```

---

### Task 4: Pre-order in the store

**Files:**
- Modify: `Sources/PokeTokenBar/Core/CompanionStore.swift` (`chooseBase`; `hatchCore`; new pre-order section after `buyEgg` with every store member below)
- Modify: `Sources/PokeTokenBar/Core/CompanionStore+Hangar.swift` (new top-level `PreorderPickStatus` only)
- Test: `Tests/PokeTokenBarTests/Gunpla/PreorderTestSupport.swift` (create), `Tests/PokeTokenBarTests/Gunpla/PreorderStoreTests.swift` (create)

**Interfaces:**
- Consumes: Task 1 fields, Task 2 `choose(… series:preorder: …)`, Task 3 `notifPreorderTitle` / `notifPreorderBody`.
- Produces:

```swift
enum PreorderPickStatus: Equatable, Sendable { case available, complete, building }

extension CompanionStore {
    /// Every catalog machine's pick status, from one collection snapshot. `building` (the active
    /// machine) wins over `complete`.
    var preorderPickStatuses: [Int: PreorderPickStatus] { get }
    var hasPreorderCandidates: Bool { get }                 // any `.available`
    /// The scaled price of the tier box of the machine's rarity (§5.4).
    func preorderPrice(_ machine: MachineRecord) -> Int
    /// Cheapest...dearest scaled box price: `price(of: .egg(.common))...price(of: .egg(.legendary))`.
    var shopPriceRange: ClosedRange<Int> { get }
    func canBuyPreorder(_ machineID: Int) -> Bool
    @discardableResult func buyPreorder(_ machineID: Int) -> Bool
}
```

`PreorderTestSupport.swift` (shared by Tasks 4–6, 8–10):

```swift
import XCTest
@testable import PokeTokenBar

/// Stores loaded from a written save, so the load-time sanitizing runs. 50B spendable unless the state says otherwise.
@MainActor
enum PreorderFixture {
    static let catalog = MachineCatalog.allBundled
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static let rx78 = 1, zaku = 2, charZaku = 3, gouf = 5, nu = 8, unicorn = 11, unicornDestroy = 100, unicornAwakened = 115

    static func id(_ machineID: Int, _ grade: GunplaGrade) -> Int
    static func store(_ state: CompanionState = CompanionState(),
                      rng: any RandomNumberGenerator = SeededRNG(seed: 7)) throws -> CompanionStore
    static func building(_ machineID: Int) -> MonState          // first grade, plan = every released grade
    static func finished(_ machineID: Int) -> DexEntry          // graduated with every released grade
    static func use(_ s: CompanionStore, _ today: Int)          // as GunplaHatchIntegrationTests.use
    static func openBox(_ s: CompanionStore) async              // as GunplaHatchIntegrationTests.openBox
    static func machineID(_ speciesID: Int?) -> Int?
}
```

`store` sets `installBaselineSet = true`, sets `usedSinceInstall = 50_000_000_000` when it is 0, writes the state as JSON to a temp file and builds `CompanionStore(provider: catalog, clock: { now }, fileURL:, rng:, defaults: UserDefaults(suiteName: "preorder-\(UUID())")!)`.

- [ ] **Step 1: Write the support file and the failing tests**

```swift
import XCTest
@testable import PokeTokenBar

@MainActor
final class PreorderStoreTests: XCTestCase {
    private typealias F = PreorderFixture

    private func state(preorder: Preorder? = nil, pending: Int? = nil, tier: Rarity? = nil) -> CompanionState {
        var s = CompanionState()
        s.preorder = preorder
        s.pendingHatchID = pending
        s.eggTier = tier
        return s
    }
    private func opened(_ s: CompanionStore) throws -> Int {
        try XCTUnwrap(F.machineID(s.state.active?.baseID))
    }

    // MARK: rolling and counting

    func test_fourthBoxBringsTheTargetAndEndsThePreorder() async throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.gouf, boxesOpened: 3)))
        await F.openBox(s)
        XCTAssertEqual(try opened(s), F.gouf)
        XCTAssertNil(s.state.preorder)
    }

    func test_otherMachineCountsOneBox() async throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.gouf, boxesOpened: 0), pending: F.id(F.zaku, .sd)))
        await F.openBox(s)
        XCTAssertEqual(try opened(s), F.zaku)
        XCTAssertEqual(s.state.preorder, Preorder(machineID: F.gouf, boxesOpened: 1))
    }

    func test_targetFromTheBoxsOwnRollEndsThePreorder() async throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.gouf, boxesOpened: 1), pending: F.id(F.gouf, .sd)))
        await F.openBox(s)
        XCTAssertEqual(try opened(s), F.gouf)
        XCTAssertNil(s.state.preorder)
    }

    func test_arrivalUsesThePreorderCopyEvenForACustomUnitOrPrayers() async throws {
        var st = state(preorder: Preorder(machineID: F.charZaku, boxesOpened: 3))
        st.eggPrayers = PrayerRecord(count: 5)
        let s = try F.store(st)
        await F.openBox(s)
        let active = try XCTUnwrap(s.state.active)
        let name = try XCTUnwrap(s.currentLine).localizedName(active.baseID, s.state.language)
        XCTAssertEqual(s.latestEvent?.text, s.l.notifPreorderBody(name))
        XCTAssertEqual(active.prayers?.count, 5, "prayers still move onto the machine")
    }

    func test_rareBoxDeliversACommonTarget() async throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.zaku, boxesOpened: 3), tier: .rare))
        await F.openBox(s)
        XCTAssertEqual(try opened(s), F.zaku)
        XCTAssertNil(s.state.preorder)
        XCTAssertNil(s.state.eggTier)
    }

    func test_preRollDiscardedByTheTierGateIsNotCounted() async throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.gouf, boxesOpened: 1), pending: F.id(F.zaku, .sd),
                                  tier: .rare))
        await F.openBox(s)
        let machine = try opened(s)
        XCTAssertNotEqual(machine, F.zaku, "the common pre-roll was discarded")
        if machine == F.gouf { XCTAssertNil(s.state.preorder) } else { XCTAssertEqual(s.state.preorder?.boxesOpened, 2) }
    }

    func test_toolPurchaseDropsThePreRollWithoutCounting() throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.gouf, boxesOpened: 2), pending: F.id(F.zaku, .sd)))
        XCTAssertTrue(s.buy(.maskingTape))
        XCTAssertNil(s.state.pendingHatchID)
        XCTAssertEqual(s.state.preorder?.boxesOpened, 2)
    }

    func test_unservablePreRollIsDroppedWithoutCounting() async throws {
        let s = try F.store(state(preorder: Preorder(machineID: F.gouf, boxesOpened: 2), pending: 25))
        F.use(s, 0)
        F.use(s, 1)   // a tick below the threshold runs the prefetch, which drops 25
        let deadline = Date().addingTimeInterval(2)
        while s.state.pendingHatchID == 25, Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertNotEqual(s.state.pendingHatchID, 25)
        XCTAssertEqual(s.state.preorder?.boxesOpened, 2)
    }

    // MARK: buying

    func test_buyingWhileHoldingABoxRerollsIt() throws {
        let s = try F.store(state(pending: F.id(F.zaku, .sd)))
        let spent = s.state.spentTokens
        XCTAssertTrue(s.buyPreorder(F.gouf))
        XCTAssertEqual(s.state.preorder, Preorder(machineID: F.gouf, boxesOpened: 0))
        XCTAssertNil(s.state.pendingHatchID)
        XCTAssertEqual(s.state.spentTokens - spent, s.price(of: .egg(.uncommon)))
    }

    func test_buyPreorderWhileBuildingKeepsTheBuild() throws {
        var st = CompanionState()
        st.active = F.building(F.zaku)
        let s = try F.store(st)
        XCTAssertTrue(s.buyPreorder(F.gouf))
        XCTAssertEqual(F.machineID(s.state.active?.baseID), F.zaku)
        XCTAssertEqual(s.state.preorder?.boxesOpened, 0)
    }

    func test_whatCannotBePreordered() throws {
        var st = CompanionState()
        st.active = F.building(F.zaku)
        st.dex = [F.finished(F.rx78)]
        let s = try F.store(st)
        XCTAssertFalse(s.canBuyPreorder(F.zaku), "being built")
        XCTAssertFalse(s.canBuyPreorder(F.rx78), "complete")
        XCTAssertFalse(s.canBuyPreorder(9_999), "unknown")
        XCTAssertTrue(s.buyPreorder(F.gouf))
        XCTAssertFalse(s.canBuyPreorder(F.charZaku), "one at a time")
        XCTAssertFalse(s.buyPreorder(F.charZaku))

        var poor = CompanionState()
        poor.usedSinceInstall = 1
        XCTAssertFalse(try F.store(poor).canBuyPreorder(F.gouf))
    }

    func test_buyPreorderChargesTheScaledPrice() throws {
        let s = try F.store()
        s.setShopDifficulty(2.0)
        let spent = s.state.spentTokens
        let gouf = try XCTUnwrap(F.catalog.machine(id: F.gouf))
        XCTAssertEqual(s.preorderPrice(gouf), PokemonBalance.scaled(FreshEgg.price(guaranteeing: .uncommon), by: 2.0))
        XCTAssertTrue(s.buyPreorder(F.gouf))
        XCTAssertEqual(s.state.spentTokens - spent, s.preorderPrice(gouf))
    }

    func test_priceFollowsTheTargetsRarity() throws {
        let s = try F.store()
        for (machine, rarity) in [(F.zaku, Rarity.common), (F.gouf, .uncommon), (F.rx78, .rare), (F.nu, .legendary)] {
            XCTAssertEqual(s.preorderPrice(try XCTUnwrap(F.catalog.machine(id: machine))), s.price(of: .egg(rarity)))
        }
        XCTAssertEqual(s.shopPriceRange, s.price(of: .egg(.common))...s.price(of: .egg(.legendary)))
    }

    func test_statusesAndCandidates() throws {
        var st = CompanionState()
        st.active = F.building(F.zaku)
        st.dex = [F.finished(F.rx78)]
        let s = try F.store(st)
        let statuses = s.preorderPickStatuses
        XCTAssertEqual(statuses.count, F.catalog.machines.count)
        XCTAssertEqual(statuses[F.zaku], .building)
        XCTAssertEqual(statuses[F.rx78], .complete)
        XCTAssertEqual(statuses[F.gouf], .available)
        XCTAssertTrue(s.hasPreorderCandidates)

        var done = CompanionState()
        done.dex = F.catalog.machines.map { F.finished($0.id) }
        XCTAssertFalse(try F.store(done).hasPreorderCandidates)
    }
}
```

- [ ] **Step 2: Run to see it fail.** `swift test --filter PreorderStoreTests`. Expected: build error, store members unknown.

- [ ] **Step 3: Implement.**
  - `chooseBase`: pass `series: state.eggSeries, preorder: state.preorder`. Add the series to the "no candidate" log line.
  - `hatchCore`: move `let machine = catalog.machine(speciesID: line.baseID)` above the tier gate and add

```swift
// A pre-ordered machine passes the gate: it was bought, and the planner put it in this box on purpose.
let isPreorderArrival = state.preorder.map { machine?.id == $0.machineID } ?? false
if let tier = state.eggTier, line.rarity.sortRank < tier.sortRank, !isPreorderArrival {
```

  - Right after `state.eggTier = nil`: `state.eggSeries = nil`, then `if isPreorderArrival { state.preorder = nil } else { state.preorder?.boxesOpened += 1 }`, with a comment that this is the only place the count changes (§5.6).
  - Notification: when `isPreorderArrival`, title `l.notifPreorderTitle` and body `l.notifPreorderBody(name)`; otherwise the existing prayer / custom / plain choice, unchanged.
  - Pre-order section after `buyEgg`, members as in Interfaces:
    - `preorderPickStatuses`: one `state.collectionSnapshot(catalog:)`; the active machine is `state.active.flatMap { catalog.machine(speciesID: $0.baseID)?.id }`; `.building` for it, `.complete` for `snapshot.isComplete`, else `.available`.
    - `preorderPrice(_:)` = `price(of: .egg(machine.rarity))`.
    - `canBuyPreorder`: `state.preorder == nil`, the machine exists, its status is `.available`, `availableTokens >= preorderPrice`.
    - `buyPreorder`: guard `canBuyPreorder`; add the price to `spentTokens`; set `Preorder(machineID:, boxesOpened: 0)`; when `state.active == nil` set `pendingHatchID = nil` and `prefetchedLineID = nil` (comment: same as a tool purchase; the held box is the pre-order's first, §5.5); `AppLog.write`; `save()`. No prefetch kick: the next update tick re-rolls, as after `buy(_:count:)`.
  - `PreorderPickStatus` at the top of `CompanionStore+Hangar.swift` with a one-line doc comment.

- [ ] **Step 4: Run.** `swift test --filter "PreorderStoreTests|GunplaHatchIntegrationTests|PremiumEggTests|ShopTests"`. Expected: all pass.

- [ ] **Step 5: Inject once.** Delete `, !isPreorderArrival` from the gate, run `test_rareBoxDeliversACommonTarget`, see it fail (the box never opens within 2 s), restore.

- [ ] **Step 6: Commit.**

```bash
git add Sources/PokeTokenBar/Core/CompanionStore.swift Sources/PokeTokenBar/Core/CompanionStore+Hangar.swift Tests/PokeTokenBarTests/Gunpla/PreorderTestSupport.swift Tests/PokeTokenBarTests/Gunpla/PreorderStoreTests.swift
git commit -m "feat(gunpla): buy pre-orders and deliver them through the box"
```

---

### Task 5: Series box in the store

**Files:**
- Modify: `Sources/PokeTokenBar/Core/CompanionStore.swift` (`buyEgg` → `restartBox`; series box section after the pre-order section)
- Test: `Tests/PokeTokenBarTests/Gunpla/SeriesBoxStoreTests.swift` (create)

**Interfaces:**
- Consumes: Task 1 `eggSeries`, Task 4 `chooseBase` wiring and `PreorderFixture`.
- Produces:

```swift
extension CompanionStore {
    /// Unfinished machines per series, custom units included (§7.2). A series with none is absent.
    var seriesBoxRemainingCounts: [String: Int] { get }
    var hasSeriesBoxCandidates: Bool { get }                 // !seriesBoxRemainingCounts.isEmpty
    /// The scaled tier box price of the series' lowest rarity (§6.3).
    func seriesBoxPrice(_ seriesID: String) -> Int
    func canBuySeriesBox(_ seriesID: String) -> Bool
    @discardableResult func buySeriesBox(_ seriesID: String) -> Bool
    /// The held box's series; nil while building. Mirrors `eggGuarantee`.
    var eggSeriesID: String? { get }
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import PokeTokenBar

@MainActor
final class SeriesBoxStoreTests: XCTestCase {
    private typealias F = PreorderFixture

    private func buildingStore(_ machineID: Int = PreorderFixture.zaku, dex: [DexEntry] = [],
                               usedSinceInstall: Int = 0) throws -> CompanionStore {
        var st = CompanionState()
        st.active = F.building(machineID)
        st.dex = dex
        st.usedSinceInstall = usedSinceInstall
        return try F.store(st)
    }
    private func machines(in series: String) -> [MachineRecord] { F.catalog.machines.filter { $0.series == series } }

    func test_seriesBoxReplacesTheBuildAndOnlyOpensThatSeries() async throws {
        let s = try buildingStore()
        let spent = s.state.spentTokens
        XCTAssertTrue(s.buySeriesBox("0080"))
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.eggSeries, "0080")
        XCTAssertEqual(s.eggSeriesID, "0080")
        XCTAssertNil(s.state.eggTier)
        XCTAssertEqual(s.state.spentTokens - spent, s.seriesBoxPrice("0080"))
        XCTAssertTrue(s.state.dex.contains { F.machineID($0.baseID) == F.zaku && $0.releasedAt != nil })
        await F.openBox(s)
        XCTAssertEqual(F.catalog.machine(speciesID: try XCTUnwrap(s.state.active).baseID)?.series, "0080")
        XCTAssertNil(s.state.eggSeries)
        XCTAssertNil(s.eggSeriesID)
    }

    func test_whatBlocksASeriesBox() throws {
        XCTAssertFalse(try F.store().canBuySeriesBox("0080"), "no build to stop")
        let s = try buildingStore()
        XCTAssertFalse(s.canBuySeriesBox("nope"))
        let done = try buildingStore(dex: machines(in: "0080").map { F.finished($0.id) })
        XCTAssertNil(done.seriesBoxRemainingCounts["0080"])
        XCTAssertFalse(done.canBuySeriesBox("0080"))
        XCTAssertFalse(try buildingStore(usedSinceInstall: 1).canBuySeriesBox("0080"))
    }

    func test_remainingCountsCustomUnits() throws {
        let s = try buildingStore(F.gouf)
        XCTAssertEqual(s.seriesBoxRemainingCounts["first"], machines(in: "first").count)
        let after = try buildingStore(F.gouf, dex: [F.finished(F.charZaku)])
        XCTAssertEqual(after.seriesBoxRemainingCounts["first"], machines(in: "first").count - 1)
    }

    func test_priceIsTheLowestRaritysTierBoxPrice() throws {
        let s = try buildingStore()
        let expected: [String: Rarity] = ["first": .common, "narrative": .uncommon, "victory": .rare,
                                          "beltorchika-children": .legendary]
        for (series, rarity) in expected { XCTAssertEqual(s.seriesBoxPrice(series), s.price(of: .egg(rarity)), series) }
    }

    func test_seriesBoxChargesTheScaledPrice() throws {
        let s = try buildingStore()
        s.setShopDifficulty(0.5)
        XCTAssertEqual(s.seriesBoxPrice("first"), PokemonBalance.scaled(FreshEgg.price(guaranteeing: .common), by: 0.5))
        let spent = s.state.spentTokens
        XCTAssertTrue(s.buySeriesBox("first"))
        XCTAssertEqual(s.state.spentTokens - spent, s.seriesBoxPrice("first"))
    }

    func test_preorderComesFirstInASeriesBox() async throws {
        var st = CompanionState()
        st.eggSeries = "0080"
        st.preorder = Preorder(machineID: F.gouf, boxesOpened: 3)
        let s = try F.store(st)
        await F.openBox(s)
        XCTAssertEqual(F.machineID(s.state.active?.baseID), F.gouf)
        XCTAssertNil(s.state.preorder)
        XCTAssertNil(s.state.eggSeries)
    }
}
```

- [ ] **Step 2: Run to see it fail.** `swift test --filter SeriesBoxStoreTests`. Expected: build error.

- [ ] **Step 3: Implement.**
  - Move everything in `buyEgg` after its guard into `private func restartBox(spending price: Int, tier: Rarity?, series: String?)`, which also sets `state.eggSeries = series` next to `state.eggTier = tier` and logs `series=`. `buyEgg` becomes the guard plus `restartBox(spending: price(of: .egg(tier)), tier: tier, series: nil)`. Keep `buyEgg`'s doc comment on `buyEgg`.
  - Series section with the members in Interfaces:
    - `seriesBoxRemainingCounts`: one snapshot; count `catalog.machines` that are not `snapshot.isComplete`, keyed by `series`.
    - `seriesBoxPrice`: the minimum `rarity.sortRank` among the series' machines, then `price(of: .egg(that rarity))` (an unknown series falls to `.egg(nil)`).
    - `canBuySeriesBox`: `hasActive`, `(seriesBoxRemainingCounts[id] ?? 0) > 0`, `availableTokens >= seriesBoxPrice(id)`.
    - `buySeriesBox`: guard, then `restartBox(spending: seriesBoxPrice(id), tier: nil, series: id)`.
    - `eggSeriesID`: `state.active == nil ? state.eggSeries : nil`.

- [ ] **Step 4: Run.** `swift test --filter "SeriesBoxStoreTests|PremiumEggTests|PreciousCompanionGuardTests|ShopTests|FreshEggTests"`. Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/PokeTokenBar/Core/CompanionStore.swift Tests/PokeTokenBarTests/Gunpla/SeriesBoxStoreTests.swift
git commit -m "feat(gunpla): sell series boxes that open one series"
```

---

### Task 6: Pick list and pick navigation

**Files:**
- Modify: `Sources/PokeTokenBar/Core/CompanionStore+Hangar.swift` (`preorderPickCells`; shared filter helper; `PreorderPickStatus.combined`)
- Modify: `Sources/PokeTokenBar/UI/PopoverView.swift` (`PopoverNavigation`)
- Test: `Tests/PokeTokenBarTests/Gunpla/PreorderPickCellsTests.swift` (create), `Tests/PokeTokenBarTests/PopoverNavigationTests.swift` (add tests)

**Interfaces:**
- Consumes: `PreorderPickStatus` (Task 4), `PreorderFixture`.
- Produces:

```swift
extension PreorderPickStatus {
    /// A hangar entry with several modes: available while any mode is, complete when all are, else building.
    static func combined(_ statuses: [PreorderPickStatus]) -> PreorderPickStatus
}

extension CompanionStore {
    /// Every catalog machine as a hangar cell (§7.3): built machines keep their owned grades, the rest are
    /// unbuilt cells, custom units included. Every filter keeps unbuilt cells, and the query matches names too.
    func preorderPickCells(query: String = "", rarity: Rarity? = nil, variantOnly: Bool = false,
                           series: String? = nil, sort: DexSortOption = .numberAsc) -> [HangarCell]
}

extension PopoverNavigation {
    var pickingPreorder: Bool                 // stored; cleared like `pickingDisplayPet`
    func openPreorderPick()                   // hangar segment, collection tab, pick mode on
    func finishPreorderPick(purchased: Bool)  // pick mode off; .home after a purchase, else back to .shop
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import PokeTokenBar

@MainActor
final class PreorderPickCellsTests: XCTestCase {
    private typealias F = PreorderFixture

    private func store(dex: [DexEntry] = []) throws -> CompanionStore {
        var st = CompanionState()
        st.language = .ko
        st.dex = dex
        return try F.store(st)
    }

    func test_listsEveryMachineIncludingUnbuiltCustomUnits() throws {
        let s = try store()
        let cells = s.preorderPickCells()
        XCTAssertEqual(Set(cells.map(\.machineID)), Set(F.catalog.machines.map(\.id)))
        XCTAssertTrue(cells.contains { $0.machineID == F.charZaku && !$0.isBuilt })
        XCTAssertFalse(s.filteredHangarCells(includeUnbuilt: true).contains { $0.machineID == F.charZaku },
                       "the normal hangar still hides unbuilt custom units")
    }

    func test_rarityAndCustomFiltersKeepUnbuiltCells() throws {
        let s = try store()
        let rare = s.preorderPickCells(rarity: .rare)
        XCTAssertTrue(rare.contains { $0.machineID == F.rx78 && !$0.isBuilt })
        XCTAssertTrue(rare.allSatisfy { F.catalog.machine(id: $0.machineID)?.rarity == .rare })
        let customs = s.preorderPickCells(variantOnly: true)
        XCTAssertTrue(customs.contains { $0.machineID == F.charZaku })
        XCTAssertTrue(customs.allSatisfy(\.isVariant))
    }

    func test_nameSearchFindsUnbuiltMachines() throws {
        let s = try store()
        XCTAssertTrue(s.preorderPickCells(query: "구프").contains { $0.machineID == F.gouf })
        XCTAssertFalse(s.filteredHangarCells(query: "구프", includeUnbuilt: true).contains { $0.machineID == F.gouf },
                       "the normal hangar still hides unbuilt names")
    }

    func test_seriesFilter() throws {
        let cells = try store().preorderPickCells(series: "0080")
        XCTAssertEqual(cells.count, F.catalog.machines.filter { $0.series == "0080" }.count)
        XCTAssertTrue(cells.allSatisfy { F.catalog.machine(id: $0.machineID)?.series == "0080" })
    }

    func test_builtCellsKeepTheirGrades() throws {
        let sd = F.id(F.zaku, .sd), hg = F.id(F.zaku, .hg)
        let entry = DexEntry(baseID: sd, finalID: hg, chainOrder: [sd, hg], rarity: .common, caughtAt: F.now,
                             releasedAt: F.now)
        let cell = try XCTUnwrap(try store(dex: [entry]).preorderPickCells().first { $0.machineID == F.zaku })
        XCTAssertEqual(cell.ownedGrades, [.sd, .hg])
    }

    func test_groupStatus() {
        XCTAssertEqual(PreorderPickStatus.combined([.complete, .available]), .available)
        XCTAssertEqual(PreorderPickStatus.combined([.complete, .complete]), .complete)
        XCTAssertEqual(PreorderPickStatus.combined([.complete, .building]), .building)
    }
}
```

Add to `PopoverNavigationTests`:

```swift
func testPreorderPickOpensTheHangarAndCancelReturnsToTheShop() {
    let nav = PopoverNavigation()
    nav.tab = .shop
    nav.showingCollectionLog = true
    nav.openPreorderPick()
    XCTAssertEqual(nav.tab, .collection)
    XCTAssertTrue(nav.pickingPreorder)
    XCTAssertFalse(nav.showingCollectionLog)
    nav.finishPreorderPick(purchased: false)
    XCTAssertEqual(nav.tab, .shop)
    XCTAssertFalse(nav.pickingPreorder)
}

func testPreorderPurchaseGoesHome() {
    let nav = PopoverNavigation()
    nav.openPreorderPick()
    nav.finishPreorderPick(purchased: true)
    XCTAssertEqual(nav.tab, .home)
    XCTAssertFalse(nav.pickingPreorder)
}

func testPreorderPickEndsWhenLeavingSwitchingOrReopening() {
    let triggers: [(String, (PopoverNavigation) -> Void)] = [
        ("other tab", { $0.tab = .home }),
        ("build log", { $0.showingCollectionLog = true }),
        ("reopen", { $0.reset() }),
        ("display-pet pick", { $0.openRepresentativeDex() }),
    ]
    for (name, trigger) in triggers {
        let nav = PopoverNavigation()
        nav.openPreorderPick()
        trigger(nav)
        XCTAssertFalse(nav.pickingPreorder, name)
    }
}

func testDisplayPetAndPreorderPicksExcludeEachOther() {
    let nav = PopoverNavigation()
    nav.openRepresentativeDex()
    nav.openPreorderPick()
    XCTAssertFalse(nav.pickingDisplayPet)
    XCTAssertTrue(nav.pickingPreorder)
}
```

- [ ] **Step 2: Run to see it fail.** `swift test --filter "PreorderPickCellsTests|PopoverNavigationTests"`. Expected: build error.

- [ ] **Step 3: Implement.**
  - Extract the filter closure of `filteredBuiltHangarCells` into `private func filterHangarCells(_ cells: [HangarCell], query: String, rarity: Rarity?, variantOnly: Bool, series: String?) -> [HangarCell]` (same rules, name from `machineName`), and use it in `filteredBuiltHangarCells` (`hangarCells`) and `preorderPickCells`.
  - `preorderPickCells`: built cells by machine ID from `hangarCells`; every other catalog machine becomes `HangarCell(machineID:, ownedGrades: [], releasedGrades: machine.grades, isVariant: machine.isVariant, isRaising: false)`; sort by `hangarOrder`; then `filterHangarCells`, then `sortHangarCells(_:by:)`.
  - `PopoverNavigation`: `var pickingPreorder = false`. Clear it wherever `pickingDisplayPet` is cleared (`tab` didSet, `showingCollectionLog` didSet when true, `reset()`), and in `openRepresentativeDex`. `openPreorderPick()` mirrors `openRepresentativeDex()` (`showSettings = false`, `showingCollectionLog = false`, `tab = .collection`, `pickingDisplayPet = false`, then `pickingPreorder = true` last). `finishPreorderPick(purchased:)` sets `pickingPreorder = false` and `tab = purchased ? .home : .shop`.

- [ ] **Step 4: Run.** `swift test --filter "PreorderPickCellsTests|PopoverNavigationTests|DexSearchAndFilterTests|HangarCellTests"`. Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/PokeTokenBar/Core/CompanionStore+Hangar.swift Sources/PokeTokenBar/UI/PopoverView.swift Tests/PokeTokenBarTests/Gunpla/PreorderPickCellsTests.swift Tests/PokeTokenBarTests/PopoverNavigationTests.swift
git commit -m "feat(gunpla): list every machine for the pre-order pick"
```

---

### Task 7: Shop cards and the series list

**Files:**
- Modify: `Sources/PokeTokenBar/UI/ShopView.swift` (`ShopView` body; `EggCard` confirm stages → `ReplaceBoxConfirmRow`; new `SeriesBoxCard`, `PreorderCard`, `PreorderActiveLine`)
- Create: `Sources/PokeTokenBar/UI/SeriesBoxListView.swift`
- Test: `Tests/PokeTokenBarTests/Gunpla/PreorderLayoutTests.swift` (create; Tasks 8 and 9 add to it)

**Interfaces:**
- Consumes: Task 3 copy, Task 4 `hasPreorderCandidates` / `shopPriceRange`, Task 5 series members, Task 6 `openPreorderPick()`.
- Produces (internal, so tests can build them):

```swift
/// "Stop building X and switch?" with [Buy] [Cancel]; a custom or legendary build asks once more.
struct ReplaceBoxConfirmRow: View { let store: CompanionStore; let prompt: String; let onCommit: () -> Void; let onCancel: () -> Void }
struct SeriesBoxCard: View { let store: CompanionStore; let onOpen: () -> Void }
struct PreorderCard: View { let store: CompanionStore; let nav: PopoverNavigation }
/// "예약 중 · {name} · 2/4번째 박스" on one line; only the name truncates.
struct PreorderActiveLine: View { let l: L; let name: String; let box: Int }
struct SeriesBoxListView: View { let store: CompanionStore; let onBack: () -> Void; let onBought: () -> Void }
```

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import PokeTokenBar

@MainActor
final class PreorderLayoutTests: XCTestCase {
    private func size<V: View>(_ view: V, width: CGFloat) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 1_000))
    }
    /// The longest machine name in that language.
    private func longestName(_ lang: AppLanguage) -> String {
        MachineCatalog.shared.machines.compactMap { lang.resolveName($0.names) }.max { $0.count < $1.count }!
    }

    func test_activePreorderLineStaysOneLine() {
        let width = PopoverMetrics.scrollContentWidth - 20   // card padding
        for lang in AppLanguage.allCases {
            let l = L(lang)
            let short = size(PreorderActiveLine(l: l, name: "A", box: 2), width: width)
            let long = size(PreorderActiveLine(l: l, name: longestName(lang), box: 4), width: width)
            XCTAssertLessThanOrEqual(long.width, width, "\(lang)")
            XCTAssertLessThanOrEqual(long.height, short.height + 1, "\(lang) wraps")
        }
    }
}
```

- [ ] **Step 2: Run to see it fail.** `swift test --filter PreorderLayoutTests`. Expected: build error.

- [ ] **Step 3: Implement.**
  - `ReplaceBoxConfirmRow`: the `.confirm` and `.preciousConfirm` rows of `EggCard`, moved as they are, with `prompt` in place of `l.eggConfirm(…)` and a private `@State` for the second stage. `EggCard` keeps `.idle` / `.confirm` and shows `ReplaceBoxConfirmRow(store:, prompt: l.eggConfirm(store.displayName, l.eggName(tier)), onCommit: commit, onCancel: { stage = .idle })`. EggCard behaviour is unchanged.
  - `ShopView`: `@State private var showingSeriesBoxes = false`. When true, show `SeriesBoxListView(store:, onBack: { showingSeriesBoxes = false }, onBought: { nav.tab = .home })` in the same 520pt frame instead of the scroll view. Otherwise, after the `ForEach`: `SeriesBoxCard(store:, onOpen: { showingSeriesBoxes = true })`, then `PreorderCard(store:, nav:)`.
  - Both cards copy `EggCard`'s card chrome (padding 10, `Color.secondary.opacity(0.06)`, radius 10). Price text `"\(l.shopPriceLabel) \(compact(range.lowerBound))~\(compact(range.upperBound))"` with `store.shopPriceRange`.
    - `SeriesBoxCard`: `SpriteView(speciesID: nil, size: 26)` icon like `EggCard`; `l.seriesBoxTitle`, `l.seriesBoxDescription`, `l.eggReleaseNote` while `hasActive`. Button area: no build → disabled [구매] and `l.eggShopLockedHint` below; no series left → disabled [구매] and `l.seriesBoxAllComplete`; balance below the range's lower bound → `l.notEnoughTokens`; else [구매] → `onOpen()`.
    - `PreorderCard`: `WorkshopIcon(.box, size: 26)`; `l.preorderTitle`, `l.preorderDescription`. With a pre-order: `PreorderActiveLine(l:, name: store.machineName(id), box: preorder.boxNumber)` and no button. Else: no candidates → disabled [구매] and `l.preorderNoCandidates`; balance below the lower bound → `l.notEnoughTokens`; else [구매] → `nav.openPreorderPick()`.
  - `PreorderActiveLine`: `HStack(spacing: 4)`: `Text("\(l.preorderActiveLabel) ·").fixedSize()`, `Text(name).lineLimit(1).truncationMode(.tail)`, `Text("· \(l.preorderBoxNumber(box))").fixedSize()`; `.font(.caption2)`, secondary.
  - `SeriesBoxListView`: header like `HangarSeriesListView` (back button `l.back`, title `l.seriesBoxTitle`); a `ScrollView` of `store.catalog.series` sorted by `order`, `.reservesScrollerLane()`. Read `seriesBoxRemainingCounts` once per body. Each row is a plain button: name (`lineLimit(1)`), `l.seriesBoxRemaining(n)`, compact `seriesBoxPrice`; disabled when the count is 0, there is no build, or the balance is below the price; opacity 0.5 when the count is 0; selected row tinted like `HangarSeriesListView`. Below the list, for the selected series: `ReplaceBoxConfirmRow(store:, prompt: l.seriesBoxConfirm(store.displayName, store.seriesName(id)), onCommit: { if store.buySeriesBox(id) { onBought() } }, onCancel: { selected = nil })`.

- [ ] **Step 4: Run.** `swift test --filter "PreorderLayoutTests|LocalizedUILiteralTests|ShopTests|PreciousCompanionGuardTests"`. Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/PokeTokenBar/UI/ShopView.swift Sources/PokeTokenBar/UI/SeriesBoxListView.swift Tests/PokeTokenBarTests/Gunpla/PreorderLayoutTests.swift
git commit -m "feat(gunpla): add series box and pre-order cards to the shop"
```

---

### Task 8: Hangar pick mode and the pre-order mark

**Files:**
- Modify: `Sources/PokeTokenBar/UI/CompanionView.swift` (`CollectionView` banner, choice state and panel; `DexGridView` pick mode; `HangarMachineCell`)
- Create: `Sources/PokeTokenBar/UI/PreorderPickPanel.swift`
- Test: `Tests/PokeTokenBarTests/Gunpla/PreorderLayoutTests.swift` (add), `Tests/PokeTokenBarTests/Gunpla/HangarCellTests.swift` (add)

**Interfaces:**
- Consumes: Task 4 `preorderPickStatuses`, `preorderPrice`, `canBuyPreorder`, `buyPreorder`; Task 6 `preorderPickCells`, `PreorderPickStatus.combined`, `pickingPreorder`, `finishPreorderPick(purchased:)`.
- Produces:

```swift
enum PreorderChoice: Equatable { case modes([Int]), machine(Int) }

/// Bottom panel of the pre-order pick: the mode list (§7.4) or the confirm row (§7.5).
struct PreorderPickPanel: View {
    let store: CompanionStore
    let choice: PreorderChoice
    let onChooseMode: (Int) -> Void
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void
}

extension HangarMachineCell {
    var preorderPick: PreorderPickStatus?   // stored, default nil = the normal hangar
    var isPreordered: Bool                  // stored, default false
    /// Pick mode draws the top released grade; otherwise the highest owned grade, or the first for a silhouette.
    static func spriteGrade(_ cell: HangarCell, preorderPick: Bool) -> GunplaGrade
}
```

- [ ] **Step 1: Write the failing tests**
  - `HangarCellTests`:

```swift
func test_spriteGradeIsTheTopGradeOnlyInThePreorderPick() {
    let built = HangarCell(machineID: 1, ownedGrades: [.sd, .hg], releasedGrades: [.sd, .hg, .rg, .mg, .verka, .pg],
                           isVariant: false, isRaising: false)
    let unbuilt = HangarCell(machineID: 5, ownedGrades: [], releasedGrades: [.sd, .hg, .mg],
                             isVariant: false, isRaising: false)
    XCTAssertEqual(HangarMachineCell.spriteGrade(built, preorderPick: true), .pg)
    XCTAssertEqual(HangarMachineCell.spriteGrade(unbuilt, preorderPick: true), .mg)
    XCTAssertEqual(HangarMachineCell.spriteGrade(built, preorderPick: false), .hg)
    XCTAssertEqual(HangarMachineCell.spriteGrade(unbuilt, preorderPick: false), .sd)
}
```

  - `PreorderLayoutTests`:

```swift
func test_pickPanelFitsWithTheLongestNames() throws {
    let longest = MachineCatalog.shared.machines.max { ($0.names["en"] ?? "").count < ($1.names["en"] ?? "").count }!
    for lang in AppLanguage.allCases {
        var st = CompanionState()
        st.language = lang
        let store = try PreorderFixture.store(st)
        for choice in [PreorderChoice.machine(longest.id), .modes([11, 100, 115])] {
            let panel = PreorderPickPanel(store: store, choice: choice, onChooseMode: { _ in }, onConfirm: { _ in },
                                          onCancel: {})
            XCTAssertLessThanOrEqual(size(panel, width: PopoverMetrics.contentWidth).width,
                                     PopoverMetrics.contentWidth, "\(lang) \(choice)")
        }
    }
}
```

- [ ] **Step 2: Run to see it fail.** `swift test --filter "PreorderLayoutTests|HangarCellTests"`. Expected: build error.

- [ ] **Step 3: Implement.**
  - `HangarMachineCell`:
    - Declare `preorderPick` and `isPreordered` (with their defaults) before `onTap`, so the existing trailing-closure call sites keep compiling.
    - `spriteGrade`: pick → `releasedGrades[releasedGrades.count - 1]`; else `ownedGrades.max() ?? releasedGrades[0]`. `sprite` encodes it for both the coloured sprite (built) and the silhouette mask (unbuilt). The normal hangar draws exactly what it drew before (`hangarRepresentativeSpeciesID` is the same grade).
    - With `preorderPick != nil`: the name is `store.machineName(cell.machineID)` even when unbuilt; `.complete` puts a `Badge(l.preorderCompleteLabel, …)` where the raising badge goes; `.building` shows `Badge(l.preorderBuildingLabel, …)` in place of the raising badge; both dim to 0.45 and `.disabled(true)`.
    - `isPreordered` (normal hangar only): `WorkshopIcon(.box, size: 12, label: store.l.preorderTitle)` at the sprite's bottom-leading corner, and `l.preorderTitle` appended to the tooltip.
  - `DexGridView`: new `let preorderPick: Bool` and `let onPickPreorder: (HangarEntry) -> Void`. In pick mode: cells from `store.preorderPickCells(query:rarity:variantOnly:series:sort:)`, the header's `all` from `store.preorderPickCells()`, statuses read once per body; each cell gets `preorderPick: PreorderPickStatus.combined(entry.cells.map { statuses[$0.machineID] ?? .complete })` and its tap calls `onPickPreorder(entry)` when that is `.available`; no `square.stack` menu; the footer shows the pager only. Normal mode: unchanged, plus `isPreordered: entry.cells.contains { $0.machineID == store.state.preorder?.machineID }`.
  - `CollectionView`:
    - `@State private var preorderChoice: PreorderChoice?`.
    - Banner when `nav.pickingPreorder && !nav.showingCollectionLog`, same layout as the display-pet banner: `l.preorderPickPrompt`, [취소] → `nav.finishPreorderPick(purchased: false)`.
    - Pass `preorderPick: nav.pickingPreorder && !nav.showingCollectionLog` and `onPickPreorder: { entry in preorderChoice = entry.cells.count > 1 ? .modes(entry.cells.map(\.machineID)) : .machine(entry.cells[0].machineID) }`.
    - `.overlay(alignment: .bottom)` on the hangar content while picking with a choice: `PreorderPickPanel(store:, choice:, onChooseMode: { preorderChoice = .machine($0) }, onConfirm: { if store.buyPreorder($0) { nav.finishPreorderPick(purchased: true) } }, onCancel: { preorderChoice = nil })`.
  - `PreorderPickPanel` (padding 10, `.regularMaterial`, radius 10, full width):
    - `.modes(ids)`: one row per mode: name (`lineLimit(1)`), `l.rarityLabel`, compact `preorderPrice`; a mode that is not `.available` shows `l.preorderCompleteLabel` or `l.preorderBuildingLabel` instead of the price and is disabled. Tap → `onChooseMode(id)`. A [취소] → `onCancel()`.
    - `.machine(id)`: line 1 `"\(modelNumber) \(name) · \(rarityLabel)"` (`lineLimit(1)`), line 2 `l.preorderOddsLine`, line 3 the compact price, then [예약] (`l.preorderShort`, prominent) when `canBuyPreorder(id)`, else `l.notEnoughTokens`, and [취소].

- [ ] **Step 4: Run.** `swift test --filter "PreorderLayoutTests|HangarCellTests|DexSearchAndFilterTests|DexBackNavigationTests|CollectionReadabilityRenderingTests|LocalizedUILiteralTests"`. Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/PokeTokenBar/UI/CompanionView.swift Sources/PokeTokenBar/UI/PreorderPickPanel.swift Tests/PokeTokenBarTests/Gunpla/PreorderLayoutTests.swift Tests/PokeTokenBarTests/Gunpla/HangarCellTests.swift
git commit -m "feat(gunpla): pick a pre-order machine in the hangar"
```

---

### Task 9: Home pre-order line and series badge

**Files:**
- Modify: `Sources/PokeTokenBar/UI/CompanionView.swift` (`CompanionHeader`; new `PreorderStatusLine`)
- Test: `Tests/PokeTokenBarTests/Gunpla/PreorderLayoutTests.swift` (add)

**Interfaces:**
- Consumes: Task 3 copy, Task 5 `eggSeriesID`.
- Produces:

```swift
/// "예약 · {name} · 이번 박스 25% (2/4)" — one line; only the name truncates.
struct PreorderStatusLine: View { let l: L; let name: String; let preorder: Preorder; let nextBox: Bool }
```

- [ ] **Step 1: Write the failing tests** in `PreorderLayoutTests`:

```swift
func test_homeLineStaysOneLine() {
    let width = PopoverMetrics.scrollContentWidth
    for lang in AppLanguage.allCases {
        for nextBox in [false, true] {
            for preorder in [Preorder(machineID: 5, boxesOpened: 1), Preorder(machineID: 5, boxesOpened: 3)] {
                let l = L(lang)
                let short = size(PreorderStatusLine(l: l, name: "A", preorder: preorder, nextBox: nextBox), width: width)
                let long = size(PreorderStatusLine(l: l, name: longestName(lang), preorder: preorder, nextBox: nextBox),
                                width: width)
                XCTAssertLessThanOrEqual(long.width, width, "\(lang) \(nextBox) \(preorder)")
                XCTAssertLessThanOrEqual(long.height, short.height + 1, "\(lang) \(nextBox) \(preorder) wraps")
            }
        }
    }
}

func test_seriesBadgeKeepsTheHeaderWidth() throws {
    for lang in AppLanguage.allCases {
        let longest = MachineCatalog.shared.series.max {
            (lang.resolveName($0.names) ?? "").count < (lang.resolveName($1.names) ?? "").count
        }!
        var st = CompanionState()
        st.language = lang
        st.eggSeries = longest.id
        let store = try PreorderFixture.store(st)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("preorder-sprites-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let header = CompanionHeader(store: store, spriteStore: SpriteStore(directory: dir))
        XCTAssertLessThanOrEqual(size(header, width: PopoverMetrics.contentWidth).width, PopoverMetrics.contentWidth,
                                 "\(lang) \(longest.id)")
    }
}
```

- [ ] **Step 2: Run to see it fail.** `swift test --filter PreorderLayoutTests`. Expected: build error (`PreorderStatusLine`).

- [ ] **Step 3: Implement.**
  - `PreorderStatusLine`: `HStack(spacing: 4)`: `WorkshopIcon(.box, size: 11)`, `Text("\(l.preorderShort) ·").fixedSize()`, `Text(name).lineLimit(1).truncationMode(.tail)`, `Text("· \(trailing)").fixedSize()`, where `trailing` is `l.preorderStatusGuaranteed(nextBox:)` when `preorder.isGuaranteedNext`, else `l.preorderStatusOdds(box: preorder.boxNumber, nextBox:)`; `.font(.caption2)`, secondary.
  - `CompanionHeader`: right after the top `HStack` (before the evolution line): `if let preorder = store.state.preorder { PreorderStatusLine(l: store.l, name: store.machineName(preorder.machineID), preorder: preorder, nextBox: store.hasActive) }`.
  - Egg row: before the guarantee badge, `if let series = store.eggSeriesID { Badge(store.l.seriesBoxHint(store.seriesName(series)), tint: .accent, style: .tinted).lineLimit(1) }`. A series box has no tier, so the two badges never show together.

- [ ] **Step 4: Run.** `swift test --filter "PreorderLayoutTests|SulkRenderTests|ZeroUsageHomeRenderingTests|LocalizedUILiteralTests"`. Expected: all pass. If the badge test fails because the badge does not shrink, give the badge `.layoutPriority(-1)` and keep the egg status text `fixedSize`; do not shorten the copy.

- [ ] **Step 5: Commit.**

```bash
git add Sources/PokeTokenBar/UI/CompanionView.swift Tests/PokeTokenBarTests/Gunpla/PreorderLayoutTests.swift
git commit -m "feat(gunpla): show the pre-order and series box on home"
```

---

### Task 10: Screens for review and the full check

**Files:**
- Create: `Tests/PokeTokenBarTests/Gunpla/PreorderRenderTests.swift`

**Interfaces:**
- Consumes: everything above, `PreorderFixture`.

- [ ] **Step 1: Write the render test.** Same shape as `EggPrayerRenderTests` (`writePNG` into an off-screen window, sprites from an empty directory, skipped unless `PTB_PREORDER_RENDER_DIR` names a folder). Write ko and en, light, at `PopoverMetrics.contentWidth`:
  - `shop-cards`: `ShopView` scrolled to the new cards, building, no pre-order (crop by rendering `VStack { SeriesBoxCard; PreorderCard }`).
  - `shop-preorder-active`: `PreorderCard` with `Preorder(machineID: 100, boxesOpened: 1)`.
  - `series-list-confirm`: `SeriesBoxListView` with "0080" selected (expose an `initialSelection: String? = nil` init parameter only if needed to render the selection; otherwise render the list unselected and the confirm row on its own).
  - `pick-mode`: `CollectionView` with a `PopoverNavigation` after `openPreorderPick()`, a few built machines in the dex, height 520.
  - `pick-modes-panel`: `PreorderPickPanel(.modes([11, 100, 115]))`; `pick-confirm-panel`: `PreorderPickPanel(.machine(5))`.
  - `home-preorder-box`, `home-preorder-building`, `home-series-badge`: `CompanionHeader` in each state.
  Label every file as sample data in the PR (sprites are placeholders).

- [ ] **Step 2: Render.** `mkdir -p /tmp/preorder-shots && PTB_PREORDER_RENDER_DIR=/tmp/preorder-shots swift test --filter PreorderRenderTests`. Look at every PNG: nothing clipped at the right edge, names truncate with "…", the pick grid shows top grades, unbuilt custom units appear as silhouettes with names.

- [ ] **Step 3: Full suite and gate.** `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1` (0 failures, count above the baseline), then `./scripts/test-gate.sh`. Expected: pass.

- [ ] **Step 4: Region coverage.** Step 3's `test-gate.sh` leaves the coverage profile in `.build`. Find the binary, profile and `llvm-cov` the way `test-gate.sh` does, and look at the new branches:

```bash
PROF=$(find .build -name 'default.profdata' | head -1)
BIN=$(find .build -name 'PokeTokenBarPackageTests' -type f ! -path '*.dSYM/*' | head -1)
SWIFT_TOOL_DIR=$(dirname "$(realpath "$(command -v swift)")")
LLVM_COV=$([[ -x "$SWIFT_TOOL_DIR/llvm-cov" ]] && echo "$SWIFT_TOOL_DIR/llvm-cov" || xcrun --find llvm-cov)
for f in Sources/PokeTokenBar/Gunpla/HatchPlanner.swift Sources/PokeTokenBar/Core/CompanionStore.swift Sources/PokeTokenBar/Core/CompanionStore+Hangar.swift Sources/PokeTokenBar/Core/SaveTransfer.swift; do
  echo "== $f"; "$LLVM_COV" show "$BIN" -instr-profile="$PROF" "$f" --show-regions | grep -n "\^0" | head -40
done
git status --short default.profraw   # must print nothing
```

  Check every `^0` that falls on a line this plan added (`preorder`, `eggSeries`, `series`, `restartBox`, `isPreorderArrival`, `preorderPick`). Cover a reachable one with a test in the owning task's test file; report an unreachable one with its line. `preorder.machineID` missing from the catalog inside `HatchPlanner.choose` is unreachable (sanitized at load) and stays uncovered.

- [ ] **Step 5: Commit.**

```bash
git add Tests/PokeTokenBarTests/Gunpla/PreorderRenderTests.swift
git commit -m "test(gunpla): render pre-order and series box screens for review"
```
