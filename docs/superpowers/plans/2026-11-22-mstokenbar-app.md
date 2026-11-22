# MSTokenBar 앱 (서브프로젝트 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PokeTokenBar를 포크해 포켓몬 층을 건프라 층으로 교체하고, 소형 개발용 데이터(12기)와 실루엣 스프라이트만으로 완전히 동작하는 macOS 메뉴바 앱을 만든다.

**Architecture:** 사용량 추적·UI·상점·세이브 코드는 그대로 두고, `CompanionStore`가 이미 주입받는 `PokeProviding` 자리에 번들 JSON 기반 `MachineCatalog`를 꽂는다. 기체×등급 한 칸을 **합성 species ID**(`100_000 + machineID*10 + gradeIndex`)로 표현해 `speciesID: Int`를 쓰는 기존 코드(진화 경로, 도감 항목, 스프라이트 키, 세이브)를 거의 그대로 재사용한다. 내부 타입 이름(`MonState`, `DexEntry`, `speciesID` 등)은 업스트림 병합을 위해 바꾸지 않고, 사용자에게 보이는 문구만 바꾼다.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, XCTest, macOS 14+. 외부 의존성 추가 없음.

**Spec:** `docs/superpowers/specs/2026-11-22-gunpla-tokenbar-design.md` (이 계획은 스펙의 §10 작업 덩어리 1 "앱"만 다룬다. 첫 공개판의 기체 데이터·도트는 별도 계획.) [첫 공개판 기체 명단](../../gunpla/initial-roster.md)

## Global Constraints

- 앱 이름 `MSTokenBar`. 「건담」「건프라」「Gundam」「Gunpla」를 앱 이름·번들 ID·아이콘·URL 스킴에 쓰지 않는다.
- 공식 일러스트·박스아트·게임 스프라이트를 저장소에 넣지 않는다. 이 계획의 스프라이트는 전부 스크립트로 생성한 실루엣.
- 후원 링크·FUNDING.yml 없음. README에 면책 문구: "Unofficial, non-commercial fan project. Not affiliated with Bandai Namco or Sunrise. All rights to the original works belong to their owners."
- 런타임 네트워크로 기체 데이터·이미지를 받지 않는다 (사용량 프로바이더의 기존 네트워크는 유지).
- 등급 순서 고정: `sd, mgsd, hg, rg, mg, pg` (gradeIndex 0…5).
- 기체는 **실제로 출시된 등급만** 거친다. 데이터에 없는 등급은 진화 경로에 절대 나타나지 않는다.
- 전용기 확률 분모: 도색 공구 0~4개 보유 시 `[32, 26, 21, 16, 12]`.
- UI 언어: `ko`, `en`, `ja` 만.
- 원본 저장소 규칙 유지: 커밋 메시지·PR은 영어, Conventional Commits. 원본 `CLAUDE.md`의 확장 규약·결함 대응 프로토콜 유지.
- 원본 LICENSE(MIT)와 저작권 표시 유지.

## Review Focus

1. **세이브 손상/구버전 필드** — 포켓몬 시절 필드(`nature`, `form`, `dittoDisguise`, `profile`)가 남아 있거나 모르는 아이템 키가 있는 세이브도 크래시 없이 로드돼야 한다. → Task 3 테스트 `test_loadsStateWithLegacyPokemonFields`.
2. **후보 풀이 비는 순간** — 일반 후보만 비거나, 전용기 후보만 비거나, 둘 다 비는 경우 각각 반대쪽 풀 / 중복 단계로 넘어가야지 박스가 영원히 안 열리면 안 된다. → Task 3 테스트 3종.
3. **보증 박스의 후보 소진** — 레어 이상을 다 졸업하면 레어 박스는 상점에서 살 수 없어야 하고, 이미 산 박스는 영원히 재시도하지 않아야 한다(구매 전에 막으므로 구매분은 항상 후보 있음). → Task 4 테스트 `test_rareBoxDisabledWhenTierExhausted`.
4. **도트 파일 누락** — 데이터에 적힌 스프라이트 파일이 번들에 없으면 실루엣으로 대체되고 크래시하지 않아야 한다. → Task 5 테스트 `test_missingSpriteFallsBackToSilhouette`.
5. **재개 등급이 마지막 등급인 미졸업 기체** — PG 단계에서 내보낸 기체가 다시 나오면 PG로 시작해 PG 임계 후 졸업해야 한다(경로 길이 1). → Task 3 테스트 `test_resumeAtFinalGradeGivesSingleStageLine`.

---

## File Structure

새 파일 (모두 `Sources/PokeTokenBar/` 아래):
- `Gunpla/GunplaGrade.swift` — 등급 enum, 합성 ID 인코딩/디코딩.
- `Gunpla/MachineCatalog.swift` — JSON 스키마(`MachineRecord`, `SeriesRecord`), 로드·구조 검증, 조회.
- `Gunpla/MachineCatalog+Provider.swift` — `PokeProviding` 구현(선형 `EvoLine` 생성).
- `Gunpla/HatchPlanner.swift` — 순수 함수: 전용기 롤 → 후보 풀 → 레어도 가중 → 재개 등급.
- `Gunpla/ToolSet.swift` — 도색 공구 순서·가격·전용기 분모.
- `Gunpla/HangarProgress.swift` — 작품별 완성도·배지(원본 `DexProgress` 대체).
- `Gunpla/BundledSprites.swift` — 번들 GIF/PNG 조회, 실루엣 폴백.
- `Core/CompanionStore+Hangar.swift` — 기체 단위 격납고 셀(`HangarCell`) 계산.
- `Resources/Gunpla/machines.json`, `Resources/Gunpla/series.json` — 개발용 12기 데이터.
- `Resources/Gunpla/Sprites/silhouette-sd.gif`, `silhouette-real.gif`, `box.png` — 생성된 플레이스홀더.
- `scripts/gen-placeholder-sprites.swift` — 플레이스홀더 생성기(ImageIO).

수정: `Package.swift`, `scripts/build-app.sh`, `Core/CompanionModel.swift`, `Core/CompanionStore.swift`, `Core/Localization.swift`, `Core/PokedexRegion.swift`(→ 삭제 후 HangarProgress), `UI/SpriteLoader.swift`, `UI/CompanionView.swift`, `UI/ShopView.swift`, `UI/BagView.swift`, `PokeTokenBarApp.swift`, `Core/AppStatePaths.swift` 외 앱 이름 문자열이 있는 곳, README 3종.

삭제(Task 9): `Core/PokeAPIClient.swift`, `Core/PokemonNameLocalization.swift`, `Core/PokemonForm.swift`(참조 제거 가능할 때만), 포켓몬 전용 테스트.

테스트: `Tests/PokeTokenBarTests/Gunpla/` 아래 새 테스트 파일들.

---

### Task 0: 포크·리브랜딩·기준선

**Files:**
- Modify: `scripts/build-app.sh`, `scripts/release.sh`, `scripts/e2e.sh`, `scripts/create-signing-cert.sh`, `Core/AppStatePaths.swift`, `PokeTokenBarApp.swift:560`, `UI/SpriteLoader.swift:20,121`, `Core/AppLog.swift`, `Core/CrashReporter.swift`, `Core/UsageStore.swift:2282`, `Core/LocalUsageCache.swift:221`, `Core/UpdateChecker.swift:47`, `Core/SaveTransfer.swift:78`, `Core/ProviderStatusChecker.swift:83`, `Core/CodexRateLimitsProvider.swift:58`, `Core/Localization.swift:1011-1013`, `README.md`, `README.ko.md`, `README.ja.md`
- Delete: `.github/FUNDING.yml`, README의 Sponsor 배지·섹션
- Create: `docs/superpowers/specs/2026-11-22-gunpla-tokenbar-design.md` (세션 폴더의 스펙 복사), 이 계획 파일 복사

- [ ] **Step 1: 사용자에게 포크 생성 확인** — GitHub에 공개 저장소를 만드는 외부 작업이다. `gh api user -q .login`으로 계정명을 확인하고, "`<login>/MSTokenBar` 공개 포크를 만들고 `~/Project/MSTokenBar`에 클론할까요?"를 묻고 승인 후 진행.
- [ ] **Step 2: 포크·클론** — `gh repo fork chattymin/PokeTokenBar --fork-name MSTokenBar --clone=false` 후 `git clone https://github.com/<login>/MSTokenBar ~/Project/MSTokenBar`, `git remote add upstream https://github.com/chattymin/PokeTokenBar`. 세션 작업 폴더를 그곳으로 옮긴다. 브랜치 `gunpla/app` 생성.
- [ ] **Step 3: 기준선 확인** — Run: `swift build && swift test 2>&1 | tail -5` / Expected: 원본 그대로 빌드·테스트 통과. 실패하는 원본 테스트가 있으면 목록을 기록해 두고(이후 회귀 판단 기준) 진행.
- [ ] **Step 4: 리브랜딩** — 위 파일들의 앱 표시명 `PokeTokenBar` → `MSTokenBar`. 번들 ID `io.github.chattymin.poketokenbar` → `io.github.<login>.mstokenbar`(LaunchAgent 라벨 `….login`·URL 타입 이름 `….agent` 포함), URL 스킴 `poketokenbar` → `mstokenbar`, Application Support 폴더 `MSTokenBar`, 업데이트 확인 repo `<login>/MSTokenBar`, 서명 ID `MSTokenBar Local`. **SwiftPM 타깃·모듈 이름 `PokeTokenBar`는 바꾸지 않는다**(업스트림 병합 비용 최소화) — 단 `build-app.sh`의 `APP_NAME`(산출 .app·실행파일 이름)은 `MSTokenBar`로, 실행파일 복사 원본은 `$(swift build --show-bin-path)/PokeTokenBar`로 분리.
- [ ] **Step 5: README 3종 교체** — 원본 소개를 걷어내고 짧은 소개 + 원본 포크 표기(링크) + Global Constraints의 면책 문구. Sponsor 배지·FUNDING 삭제.
- [ ] **Step 6: 검증** — Run: `swift build && swift test 2>&1 | tail -5 && PTB_NATIVE_ARCH_ONLY=1 scripts/build-app.sh` / Expected: Step 3과 같은 테스트 결과, `build/MSTokenBar.app` 생성. `grep -rn "chattymin/PokeTokenBar\|io.github.chattymin" Sources scripts` 결과는 `upstream` 언급·LICENSE 외 0건.
- [ ] **Step 7: Commit** — `git commit -am "chore: rebrand fork as MSTokenBar"` (+ 스펙·계획 파일 add)

---

### Task 1: 등급·합성 ID·카탈로그 로드

**Files:**
- Create: `Sources/PokeTokenBar/Gunpla/GunplaGrade.swift`, `Sources/PokeTokenBar/Gunpla/MachineCatalog.swift`, `Sources/PokeTokenBar/Resources/Gunpla/machines.json`, `Sources/PokeTokenBar/Resources/Gunpla/series.json`
- Modify: `Package.swift` (executableTarget에 `resources: [.copy("Resources/Gunpla")]`)
- Test: `Tests/PokeTokenBarTests/Gunpla/MachineCatalogTests.swift`

**Interfaces:**
- Produces:
  - `enum GunplaGrade: String, Codable, CaseIterable, Comparable, Sendable { case sd, mgsd, hg, rg, mg, pg }` — `var index: Int` (0…5), `var label: String` ("SD","MGSD","HG","RG","MG","PG"), `var bodyType: BodyType`
  - `enum BodyType: String, Sendable { case sd, real }` — sd/mgsd → `.sd`, 나머지 → `.real`
  - `enum GunplaID { static let base = 100_000; static func encode(machineID: Int, grade: GunplaGrade) -> Int; static func decode(_ speciesID: Int) -> (machineID: Int, grade: GunplaGrade)?; static func isGunpla(_ speciesID: Int) -> Bool }`
  - `struct MachineRecord: Codable, Sendable { let id: Int; let modelNumber: String; let names: [String: String]; let series: String; let faction: String; let rarity: Rarity; let grades: [GunplaGrade]; let gradeSources: [String: String]?; let variantOf: Int?; let sprites: SpriteNames?; var isVariant: Bool { variantOf != nil } }` — `gradeSources`(등급 rawValue → 출처 URL)는 이 계획에선 선택 필드. 필수 검사는 데이터 계획의 검증 스크립트가 맡는다. `struct SpriteNames: Codable, Sendable { let sd: String?; let real: String? }`
  - `struct SeriesRecord: Codable, Sendable { let id: String; let names: [String: String]; let order: Int }`
  - `struct MachineCatalog: Sendable { init(machines: [MachineRecord], series: [SeriesRecord]) throws; static func bundled() throws -> MachineCatalog; let machines: [MachineRecord]; let series: [SeriesRecord]; func machine(_ id: Int) -> MachineRecord?; func machine(speciesID: Int) -> MachineRecord?; static let shared: MachineCatalog }`
  - `enum CatalogError: Error, Equatable { case duplicateID(Int); case emptyGrades(Int); case unsortedGrades(Int); case unknownSeries(Int, String); case unknownVariantBase(Int, Int); case variantOfVariant(Int); case idOutOfRange(Int); case missingName(Int, String) }`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
func test_encodeDecodeRoundTrip() {
    let id = GunplaID.encode(machineID: 12, grade: .hg)
    XCTAssertEqual(id, 100_122)
    XCTAssertEqual(GunplaID.decode(id)?.machineID, 12)
    XCTAssertEqual(GunplaID.decode(id)?.grade, .hg)
    XCTAssertNil(GunplaID.decode(25))          // 포켓몬 범위는 건프라 아님
    XCTAssertNil(GunplaID.decode(100_126))     // gradeIndex 6 없음
}
func test_gradeBodyType() {
    XCTAssertEqual(GunplaGrade.mgsd.bodyType, .sd)
    XCTAssertEqual(GunplaGrade.hg.bodyType, .real)
    XCTAssertEqual(GunplaGrade.allCases.map(\.label), ["SD","MGSD","HG","RG","MG","PG"])
}
func test_bundledCatalogLoadsAndIsValid() throws {
    let c = try MachineCatalog.bundled()
    XCTAssertEqual(c.machines.count, 12)
    XCTAssertFalse(c.machines.filter { $0.variantOf != nil }.isEmpty)
}
func test_rejectsInvalidRecords() {
    // 각 CatalogError 케이스마다 하나: 중복 id, 빈 grades, 순서가 뒤바뀐 grades([.mg,.hg]),
    // 없는 series, 없는 variantOf, 전용기의 전용기, id 0 또는 ≥ 10_000, names에 ko/en/ja 중 하나 누락
    XCTAssertThrowsError(try MachineCatalog(machines: [m(1), m(1)], series: [s])) {
        XCTAssertEqual($0 as? CatalogError, .duplicateID(1))
    }
    // … 나머지 7케이스 동일 패턴
}
```

- [ ] **Step 2: 실패 확인** — Run: `swift test --filter MachineCatalogTests` / Expected: 컴파일 실패(`GunplaID` 미정의).
- [ ] **Step 3: 구현** — 위 Interfaces 그대로. `machineID`는 1…9_999. `bundled()`는 `Bundle.module`에서 `Gunpla/machines.json`, `Gunpla/series.json`을 읽는다. `shared`는 `try! bundled()` (번들 데이터는 Task 1 테스트가 보증).
- [ ] **Step 4: 개발용 데이터 12기 작성** — 아래 표 그대로. **"dev sample — grades unverified"** 주석 필드를 JSON 최상위에 둔다(데이터 계획에서 교체). series: `first`(order 0, 퍼스트/Mobile Suit Gundam/機動戦士ガンダム), `zeta`(1), `cca`(2), `uc`(3).

| id | modelNumber | ko | series | faction | rarity | grades | variantOf |
|---|---|---|---|---|---|---|---|
| 1 | RX-78-2 | 건담 | first | efsf | rare | sd,mgsd,hg,rg,mg,pg | |
| 2 | MS-06F | 자쿠 II | first | zeon | common | sd,hg,rg,mg,pg | |
| 3 | MS-06S | 샤아 전용 자쿠 II | first | zeon | rare | sd,hg,rg,mg | 2 |
| 4 | RGM-79 | 짐 | first | efsf | common | hg,mg | |
| 5 | MS-07B | 구프 | first | zeon | uncommon | hg,mg | |
| 6 | RX-178 | 건담 Mk-II | zeta | aeug | rare | hg,rg,mg,pg | |
| 7 | MSZ-006 | 제타 건담 | zeta | aeug | rare | hg,rg,mg,pg | |
| 8 | RX-93 | ν 건담 | cca | londo_bell | legendary | sd,hg,rg,mg | |
| 9 | MSN-04 | 사자비 | cca | neo_zeon | legendary | sd,hg,rg,mg | |
| 10 | RGZ-91 | 리 가지 | cca | londo_bell | common | hg,mg | |
| 11 | RX-0 | 유니콘 건담 | uc | londo_bell | legendary | sd,hg,rg,mg,pg | |
| 12 | MS-06R-2 | 조니 라이덴 전용 자쿠 II | first | zeon | rare | mg | 2 |

  (12번은 단일 등급 전용기 테스트용 개발 데이터. 실제 데이터셋 규칙(MSV 제외)과 무관.) en/ja 이름도 채운다.
- [ ] **Step 5: 통과 확인** — Run: `swift test --filter MachineCatalogTests` / Expected: PASS.
- [ ] **Step 6: Commit** — `feat(gunpla): add grade model, synthetic ids and bundled catalog`

---

### Task 2: 카탈로그를 `PokeProviding`으로

**Files:**
- Create: `Sources/PokeTokenBar/Gunpla/MachineCatalog+Provider.swift`
- Modify: `Sources/PokeTokenBar/PokeTokenBarApp.swift:107` (`CompanionStore(provider: MachineCatalog.shared, detailProvider: nil)`)
- Test: `Tests/PokeTokenBarTests/Gunpla/CatalogProviderTests.swift`

**Interfaces:**
- Consumes: Task 1 전부.
- Produces: `extension MachineCatalog: PokeProviding` —
  - `func line(baseSpeciesID: Int) async throws -> EvoLine` : `baseSpeciesID`가 가리키는 기체의 출시 등급 중 **그 등급부터 끝까지**를 선형 `EvoNode` 체인으로. `rarity` = 기체 rarity. `names[speciesID]` = 언어별 `"\(grade.label) \(machineName)"` (예: ko `"HG 건담"`).
  - `func baseSpeciesIndex() async throws -> [BaseSpecies]` : 사용하지 않음 — 빈 배열 반환(부화 선택은 Task 3의 HatchPlanner가 담당).
  - `func baseSpecies(id: Int) async throws -> BaseSpecies?` : `nil`.
  - `enum CatalogProviderError: Error { case unknownSpecies(Int), unreleasedGrade(Int) }`

- [ ] **Step 1: 실패하는 테스트**

```swift
func test_lineFromFirstGradeCoversAllReleasedGrades() async throws {
    let line = try await MachineCatalog.shared.line(baseSpeciesID: GunplaID.encode(machineID: 2, grade: .sd))
    XCTAssertEqual(pathIDs(line.tree), [.sd,.hg,.rg,.mg,.pg].map { GunplaID.encode(machineID: 2, grade: $0) })
    XCTAssertEqual(line.totalForms, 5)
    XCTAssertEqual(line.rarity, .common)
    XCTAssertEqual(line.localizedName(GunplaID.encode(machineID: 2, grade: .hg), .ko), "HG 자쿠 II")
}
func test_lineFromResumedGradeStartsThere() async throws {
    let line = try await MachineCatalog.shared.line(baseSpeciesID: GunplaID.encode(machineID: 1, grade: .rg))
    XCTAssertEqual(line.totalForms, 3) // rg, mg, pg
}
func test_singleGradeMachineHasOneStage() async throws {
    let line = try await MachineCatalog.shared.line(baseSpeciesID: GunplaID.encode(machineID: 12, grade: .mg))
    XCTAssertEqual(line.totalForms, 1)
}
func test_unreleasedGradeThrows() async {
    await XCTAssertThrowsErrorAsync(try await MachineCatalog.shared.line(baseSpeciesID: GunplaID.encode(machineID: 4, grade: .rg)))
}
```

- [ ] **Step 2: 실패 확인** — `swift test --filter CatalogProviderTests` / FAIL.
- [ ] **Step 3: 구현** — 위 시그니처. `EvoNode(speciesID:children:)`로 뒤에서부터 체인 조립.
- [ ] **Step 4: 통과 확인** — PASS.
- [ ] **Step 5: Commit** — `feat(gunpla): serve linear grade lines through PokeProviding`

---

### Task 3: 부화 규칙 (전용기 먼저 → 중복 없음 → 재개 등급)

**Files:**
- Create: `Sources/PokeTokenBar/Gunpla/HatchPlanner.swift`, `Sources/PokeTokenBar/Gunpla/ToolSet.swift`(분모 부분만)
- Modify: `Core/CompanionStore.swift` — `chooseBase()`(1912), `chooseBaseViaREST()` 삭제, `hatchCore`(1739)의 shiny/nature/ditto/form/profile 롤, `shinyDenominator`(1726-1736); `Core/CompanionModel.swift` — `PokemonOdds.shinyDenominator` 제거
- Test: `Tests/PokeTokenBarTests/Gunpla/HatchPlannerTests.swift`, `Tests/PokeTokenBarTests/Gunpla/GunplaHatchIntegrationTests.swift`

**Interfaces:**
- Consumes: Task 1~2, `ToolSet.shinyDenominator(toolLevel:)`(Task 4 — 이 태스크에서는 `toolLevel` 정수를 인자로 받기만 한다).
- Produces:
  - `struct CollectionSnapshot: Sendable { let graduatedMachineIDs: Set<Int>; let highestReachedGrade: [Int: GunplaGrade] }` — `highestReachedGrade`는 **졸업 안 한** 기체만 담는다.
  - `extension CompanionState { func collectionSnapshot(catalog: MachineCatalog) -> CollectionSnapshot }` — `dex`의 `releasedAt == nil` 항목의 `finalID`로 졸업 기체, 모든 `dex` 항목 `chainOrder`(+ `active`의 도달분)로 최고 도달 등급.
  - `enum HatchPlanner { static let rarityWeight: [Rarity: Int] = [.common: 100, .uncommon: 40, .rare: 12, .legendary: 3]; static func choose(catalog: MachineCatalog, snapshot: CollectionSnapshot, tier: Rarity?, toolLevel: Int, rng: inout any RandomNumberGenerator) -> HatchChoice? }` (`CompanionStore.rng`가 `any RandomNumberGenerator`라 그대로 넘긴다)
  - `struct HatchChoice: Equatable { let startSpeciesID: Int; let isVariant: Bool; let isDuplicatePhase: Bool }`
  - `static func hasCandidates(catalog:snapshot:tier:) -> Bool` (Task 4 상점이 사용)

**알고리즘 (`choose`)** — 시그니처와 테스트만으로 정해지지 않는 부분:
```
eligible(m) = (tier == nil || m.rarity.sortRank >= tier!.sortRank)
variants = catalog.machines.filter { isVariant && eligible && !graduated }
bases    = catalog.machines.filter { !isVariant && eligible && !graduated }
wantVariant = rng.next() % ToolSet.shinyDenominator(toolLevel) == 0
pool = wantVariant ? (variants.nonEmpty ?? bases) : (bases.nonEmpty ?? variants)
if pool empty: 중복 단계 → pool = catalog.machines.filter { eligible && isVariant == wantVariant } (비면 반대쪽), 그래도 비면 nil
pick = 레어도 가중 1회 롤(rarityWeight)
start = 중복 단계면 pick.grades.first, 아니면 highestReachedGrade[pick.id] ?? pick.grades.first
return HatchChoice(startSpeciesID: encode(pick.id, start), isVariant: pick.variantOf != nil, isDuplicatePhase: …)
```

- [ ] **Step 1: 실패하는 테스트 (HatchPlannerTests)** — 결정적 RNG(`SeededRNG`, 원본 테스트에 있는 것 재사용; 없으면 고정 시퀀스 RNG를 테스트 지원 파일로 추가)로:

```swift
func test_neverPicksGraduatedMachine()            // 1~11 졸업 → 1000회 롤 모두 id 12, isDuplicatePhase == false
func test_variantRollPicksFromVariantPool()       // 분모 롤이 0이 되는 시퀀스 → isVariant == true, id ∈ {3,12}
func test_variantsObtainableAfterBaseGraduated()  // 2 졸업 상태에서 전용기 롤 → id 3 가능
func test_emptyVariantPoolFallsBackToBases()      // 3,12 졸업 + 전용기 롤 → isVariant == false
func test_emptyBasePoolFallsBackToVariants()      // 모든 일반 기체 졸업 + 일반 롤 → isVariant == true
func test_allGraduatedEntersDuplicatePhase()      // 전부 졸업 → isDuplicatePhase == true, start == grades.first
func test_resumesFromHighestReachedGrade()        // highestReachedGrade[1] = .hg, 1만 남김 → startSpeciesID == encode(1,.hg)
func test_resumeAtFinalGradeGivesSingleStageLine() async // [1] = .pg → line(start).totalForms == 1
func test_tierFiltersCandidates()                 // tier .rare → 고른 기체 rarity ∈ {rare, legendary}
func test_toolLevelChangesVariantOdds()           // toolLevel 0 → 분모 32, 4 → 12 (롤 값 % 분모 판정 경계)
```

- [ ] **Step 2: 실패 확인** — `swift test --filter HatchPlannerTests` / FAIL.
- [ ] **Step 3: `HatchPlanner` 구현** — 위 Interfaces와 알고리즘.
- [ ] **Step 4: 통과 확인** — PASS.
- [ ] **Step 5: CompanionStore 연결** —
  - `chooseBase()` 본문을 `HatchPlanner.choose(catalog: .shared, snapshot: state.collectionSnapshot(catalog: .shared), tier: state.eggTier, toolLevel: toolLevel, rng: &rng)?.startSpeciesID`로 교체. `chooseBaseViaREST()` 삭제. (`var toolLevel: Int { 0 }`를 임시로 두고 Task 4가 같은 이름으로 실제 계산으로 바꾼다.) 임시 분모 함수가 필요하므로 `ToolSet.swift`에 `denominators`·`shinyDenominator(toolLevel:)`만 이 태스크에서 먼저 만든다(Task 4가 나머지를 채움).
  - `hatchCore`: `isShiny = MachineCatalog.shared.machine(speciesID: line.baseID)?.variantOf != nil` (롤하지 않음). `nature = nil`, `dittoDisguise = nil`, `form = nil`, `profile = nil`. `hasGrowthBoost`는 그대로(중복 단계에서만 true가 됨).
  - `PokeTokenBarApp`의 `CompanionStore(...)` 생성 시 `dittoDisguiseRollingEnabled: false`.
- [ ] **Step 6: 통합 테스트 (GunplaHatchIntegrationTests)** — 원본 `CompanionTests`의 스토어 생성 패턴(임시 상태 파일 URL, 주입 clock/rng)을 따라:

```swift
func test_hatchFromBoxProducesCatalogMachineAtStartGrade()   // eggUsage ≥ eggHatchThreshold → active.baseID decode 성공, stageIndex 0
func test_variantHatchIsShiny()                              // 전용기 롤 시퀀스 → active.isShiny == true, machine.variantOf != nil
func test_graduationRecordsAllGradeCellsInDex()              // id 2를 PG까지 → dex 마지막 항목 chainOrder 5칸
func test_releasedMidwayResumesAtReachedGrade()              // id 1을 HG까지 키우고 buyEgg(nil) → 다음 부화가 1이면 baseID == encode(1,.hg)
func test_loadsStateWithLegacyPokemonFields()                // nature/form/dittoDisguise/profile/mint 인벤토리가 든 JSON → 로드 성공, active 유지
```

- [ ] **Step 7: 통과 + 깨진 원본 테스트 정리** — Run: `swift test 2>&1 | tail -30`. 이 태스크 때문에 깨지는 포켓몬 전용 테스트(`DittoTests`, `PremiumEggTests`의 capture_rate 경로, `CompanionTests`의 PokeAPI 스텁 기반 부화 등)는 **삭제가 아니라** 건프라 의미로 고칠 수 있으면 고치고, 개념 자체가 사라진 것(메타몽, 성격, 폼 롤)은 삭제. 삭제 목록을 커밋 본문에 적는다.
- [ ] **Step 8: Commit** — `feat(gunpla): variant-first, no-duplicate hatching with grade resume`

---

### Task 4: 아이템 — 스펀지 사포·도색 공구·박스 보증 소진

**Files:**
- Modify: `Sources/PokeTokenBar/Gunpla/ToolSet.swift`(Task 3에서 만든 분모 부분에 나머지 추가), `Core/CompanionModel.swift` (`ItemKind` 182-218, `Mint`·`ShinyCharm` 삭제), `Core/CompanionStore.swift` (`ownsShinyCharm`, `isPurchasedPassive`, `canBuy`, `buy`, `canBuyEgg`, `useMint` 삭제, `toolLevel`), `UI/ShopView.swift`, `UI/BagView.swift`, `UI/CompanionView.swift`(민트·성격 표시 제거)
- Test: `Tests/PokeTokenBarTests/Gunpla/ToolSetTests.swift`; 삭제 `MintTests.swift`, `ShinyCharmTests.swift`

**Interfaces:**
- Consumes: Task 3 `HatchPlanner.hasCandidates`.
- Produces:
  - `ItemKind` cases: `rareCandy`(rawValue 유지, 표시명 스펀지 사포), `maskingTape`, `panelLinePen`, `paintSet`, `airbrush`. 모두 `spriteName == nil`(이모지 폴백: 🧽 🩹 🖊️ 🎨 💨). 공구 4종 `isPassive == true`.
  - `enum ToolSet { static let order: [ItemKind] = [.maskingTape, .panelLinePen, .paintSet, .airbrush]; static let prices: [ItemKind: Int] = [.maskingTape: 1_000_000_000, .panelLinePen: 1_500_000_000, .paintSet: 2_000_000_000, .airbrush: 3_000_000_000]; static let denominators: [UInt64] = [32, 26, 21, 16, 12]; static func shinyDenominator(toolLevel: Int) -> UInt64; static func level(inventory: [String: Int]) -> Int /* order의 앞에서부터 연속 보유 개수 */; static func nextPurchasable(inventory:) -> ItemKind? }`
  - `CompanionStore.toolLevel: Int { ToolSet.level(inventory: state.inventory) }`, `shinyDenominator`는 `ToolSet.shinyDenominator(toolLevel:)` 사용(알림 문구도 같은 값).
  - `canBuy(_ kind:)`: 공구는 `kind == ToolSet.nextPurchasable(...)`이고 잔액 충분할 때만. `canBuyEgg(_ tier:)`: 기존 조건 && `tier == nil || HatchPlanner.hasCandidates(catalog:snapshot:tier:)`.

- [ ] **Step 1: 실패하는 테스트**

```swift
func test_denominatorsByLevel() { XCTAssertEqual((0...4).map { ToolSet.shinyDenominator(toolLevel: $0) }, [32,26,21,16,12]) }
func test_levelCountsOnlyContiguousPrefix() { XCTAssertEqual(ToolSet.level(inventory: ["maskingTape":1, "paintSet":1]), 1) }
func test_toolsMustBeBoughtInOrder()          // 스토어: 잔액 충분, 아무것도 없음 → canBuy(.panelLinePen) == false, canBuy(.maskingTape) == true
func test_ownedToolCannotBeBoughtAgain()
func test_rareBoxDisabledWhenTierExhausted()  // rare/legendary 전부 졸업 → canBuyEgg(.rare) == false, canBuyEgg(nil) == true
func test_spongeKeepsRareCandyGrantRules()    // 기존 RareCandyTests 중 지급 규칙 테스트가 그대로 통과(rawValue 유지)
```

- [ ] **Step 2: 실패 확인** — `swift test --filter ToolSetTests` / FAIL.
- [ ] **Step 3: 구현** — Interfaces대로. 상점 정렬은 원본 `isPurchasedPassive` 정렬 규칙 유지(보유 공구는 뒤로). 상점에는 다음 공구 하나만 활성, 이후 공구는 잠금 표시. 비활성 박스에는 Task 8 문구 `hangarTierComplete` 표시.
- [ ] **Step 4: 통과 확인** — `swift test 2>&1 | tail -20` / PASS(삭제한 테스트 제외).
- [ ] **Step 5: Commit** — `feat(gunpla): sponge sanding item, ordered paint tool set, exhausted box guard`

---

### Task 5: 번들 스프라이트·실루엣·등급 연출

**Files:**
- Create: `scripts/gen-placeholder-sprites.swift`, `Sources/PokeTokenBar/Resources/Gunpla/Sprites/{silhouette-sd.gif,silhouette-real.gif,box.png}`, `Sources/PokeTokenBar/Gunpla/BundledSprites.swift`
- Modify: `UI/SpriteLoader.swift` (`SpriteStore.data(speciesID:...)` 47-66, `eggData()` 88-100, `data(itemName:)` 74), `UI/CompanionView.swift`·`UI/FloatingPetPanel.swift`(등급 배지·크기)
- Test: `Tests/PokeTokenBarTests/Gunpla/BundledSpritesTests.swift`

**Interfaces:**
- Consumes: Task 1 (`GunplaID.decode`, `MachineRecord.sprites`, `GunplaGrade.bodyType`).
- Produces:
  - `enum BundledSprites { static func gifData(speciesID: Int, catalog: MachineCatalog = .shared, bundle: Bundle = .module) -> Data?; static func boxPNG(bundle: Bundle = .module) -> Data?; static func resourceName(speciesID: Int, catalog: MachineCatalog) -> String? }` — 해당 등급 체형의 `sprites.sd`/`sprites.real` 파일이 번들에 있으면 그것, 없으면 `silhouette-sd` / `silhouette-real`.
  - `GunplaGrade.displayScale: CGFloat` — sd 0.85, mgsd 1.0, hg 0.8, rg 0.88, mg 0.95, pg 1.05 (같은 체형 안에서 등급이 오를수록 커짐). 등급 배지는 스프라이트 우하단에 `grade.label` 캡슐.
  - `SpriteStore.data(speciesID:animated:shiny:form:back:)`: 건프라 ID면 `back == true` → `nil`(원본의 "뒷모습 없음 → 앞모습" 경로를 탄다), `animated == true` → `gifData`, `false` → GIF 첫 프레임을 PNG로 인코딩. 네트워크 경로는 건프라 ID에서 절대 타지 않는다. `eggData()` → `boxPNG()`.
- 플레이스홀더 생성기: 48×48(SD) / 48×64(리얼) 실루엣 2프레임(1px 위아래 들썩임, 프레임 지연 0.4s), 32×32 박스. 단색 회색, 투명 배경. `swift scripts/gen-placeholder-sprites.swift <outdir>`.

- [ ] **Step 1: 실패하는 테스트**

```swift
func test_missingSpriteFallsBackToSilhouette()   // 개발 데이터 sprites 전부 nil → resourceName(encode(1,.hg)) == "silhouette-real"
func test_sdGradesUseSdSilhouette()              // encode(1,.mgsd) → "silhouette-sd"
func test_gifDataIsAnimated()                    // gifData 결과를 CGImageSource로 열면 프레임 수 ≥ 2
func test_backSpriteIsNilForGunpla() async       // SpriteStore.shared.data(speciesID: encode(1,.hg), animated: true, back: true) == nil
func test_gunplaSpriteNeverHitsNetwork() async   // URLProtocol 스텁으로 요청 0건 확인
```

- [ ] **Step 2: 실패 확인** — FAIL.
- [ ] **Step 3: 생성기 작성·실행** — Run: `swift scripts/gen-placeholder-sprites.swift Sources/PokeTokenBar/Resources/Gunpla/Sprites` / Expected: 3개 파일 생성.
- [ ] **Step 4: 구현** — Interfaces대로. 등급 배지·`displayScale`은 메뉴바 스프라이트, 홈 카드, 플로팅 펫, 격납고 셀에 적용.
- [ ] **Step 5: 통과 확인** — PASS. `PTB_NATIVE_ARCH_ONLY=1 scripts/build-app.sh` 후 `.app` 안에 리소스 번들(`PokeTokenBar_PokeTokenBar.bundle`)이 들어있는지 확인 — 없으면 `build-app.sh`에 `cp -R "$(swift build -c release --show-bin-path)/PokeTokenBar_PokeTokenBar.bundle" "$APP/Contents/Resources/"` 추가.
- [ ] **Step 6: 수동 확인** — 앱 실행, 메뉴바에 박스 → (테스트용 난이도 0.1) 부화 후 실루엣 애니메이션 + 등급 배지 표시. 스크린샷을 `docs/pr-images/gunpla-sprites.png`로 저장.
- [ ] **Step 7: Commit** — `feat(gunpla): bundled sprites with silhouette fallback and grade badges`

---

### Task 6: 격납고 — 기체 단위 셀·작품 카테고리·배지

**Files:**
- Create: `Sources/PokeTokenBar/Gunpla/HangarProgress.swift`, `Sources/PokeTokenBar/Core/CompanionStore+Hangar.swift`
- Delete: `Core/PokedexRegion.swift` (내용을 HangarProgress로 대체), `Tests/PokeTokenBarTests/PokedexRegionTests.swift`, `UnownSprite*Tests.swift`, `GenerationDexScreenshotTests.swift`
- Modify: `Core/CompanionStore.swift` (`dexCompletions`, `nationalDexProgress`, `earnedDexBadges`, `dexCompletionNotification`), `UI/CompanionView.swift` (도감 그리드·지역 칩·상세), `Core/Localization.swift`(배지 문구)
- Test: `Tests/PokeTokenBarTests/Gunpla/HangarProgressTests.swift`, `Tests/PokeTokenBarTests/Gunpla/HangarCellTests.swift`

**Interfaces:**
- Consumes: Task 1, `CompanionStore.dexSpecies`(합성 ID 단위, 기존).
- Produces:
  - `struct HangarCell: Identifiable, Sendable { let machineID: Int; let ownedGrades: Set<GunplaGrade>; let releasedGrades: [GunplaGrade]; let isVariant: Bool; let isRaising: Bool; var id: Int { machineID } }`
  - `extension CompanionStore { var hangarCells: [HangarCell] }` — `dexSpecies`를 `GunplaID.decode`로 묶음. 정렬: series.order, 그다음 machine id.
  - `struct SeriesCompletion: Identifiable, Sendable, Equatable { let seriesID: String; let ownedCells: Int; let totalCells: Int; let variantOwnedCells: Int; let variantTotalCells: Int; var isComplete: Bool; var isVariantComplete: Bool; var id: String { seriesID } }` — 셀 = (기체, 출시 등급). 일반 기체와 전용기를 따로 센다.
  - `enum DexBadge` 교체: `case series(String)`, `seriesVariant(String)`, `all`, `allVariant`. `notificationKey`: `"series.<id>"`, `"seriesVariant.<id>"`, `"all"`, `"allVariant"`.
  - `enum HangarProgress { static func completions(owned: [HangarCell], catalog: MachineCatalog) -> [SeriesCompletion]; static func earnedBadges(_ completions: [SeriesCompletion]) -> [DexBadge]; static func newlyEarnedBadges(earned:alreadyNotified:) -> [DexBadge] }` — 전용기가 없는 작품은 `seriesVariant` 배지 대상 아님.
  - UI: 지역 칩 자리에 `catalog.series` 순서대로 작품 칩(전체 + 작품들). 셀 하나 = 기체 하나, 셀 안에 출시 등급 라벨을 나열하고 보유 등급은 강조, 미보유는 흐리게. 전용기 셀은 ✨. 상세 화면: 등급별 스프라이트 줄(보유분만 스프라이트, 미보유는 실루엣), 형식번호·소속·작품(Task 7).

- [ ] **Step 1: 실패하는 테스트**

```swift
func test_cellsGroupGradesByMachine()            // dex에 id 2 chainOrder [sd,hg] + active id 2 path [rg] 도달 → 셀 1개, ownedGrades {sd,hg,rg}
func test_seriesCompletionCountsReleasedCellsOnly() // first: 일반(1,2,4,5) 셀 = 6+5+2+2 = 15, 전용기(3,12) = 4+1 = 5
func test_seriesBadgeWhenAllBaseCellsOwned()
func test_variantBadgeSeparate()
func test_seriesWithoutVariantsHasNoVariantBadge() // zeta → seriesVariant 배지 없음
func test_badgeKeysStable()                      // notificationKey 문자열 고정
```

- [ ] **Step 2: 실패 확인** — FAIL.
- [ ] **Step 3: 구현** — Interfaces대로. `seedDexCompletionsIfNeeded`·`checkDexCompletions` 흐름은 그대로 두고 데이터 원천만 교체. 원본 `DexSearchAndFilterTests`·`DexBackNavigationTests`는 셀 단위에 맞게 수정.
- [ ] **Step 4: 통과 확인** — `swift test 2>&1 | tail -20` / PASS.
- [ ] **Step 5: 수동 확인** — 앱에서 격납고 열기, 작품 칩 전환, 셀·상세 표시. 스크린샷 `docs/pr-images/gunpla-hangar.png`.
- [ ] **Step 6: Commit** — `feat(gunpla): hangar with machine cells, series filters and badges`

---

### Task 7: 기체 프로필로 교체

**Files:**
- Modify: `UI/CompanionView.swift`(프로필·타입·능력치·기술 섹션), `Core/CompanionStore.swift`(`loadPokemonDetails`, `preparePokemonProfiles`, `enrichProfiles`, `migratePokemonProfilesIfNeeded`, `reconcileActiveProfileGrowth`, `pokemonDetailsByID`), `PokeTokenBarApp.swift`
- Delete: `Tests/PokeTokenBarTests/PokemonProfileTests.swift`, `PokemonTypeColorTests.swift`, `ProfileGrowthIntegrationTests.swift`, `FormMetadataNoteRenderingTests.swift`
- Test: `Tests/PokeTokenBarTests/Gunpla/MachineProfileTests.swift`

**Interfaces:**
- Produces: `struct MachineProfile: Equatable, Sendable { let modelNumber: String; let factionKey: String; let seriesID: String; let releasedGrades: [GunplaGrade] }`, `extension MachineCatalog { func profile(speciesID: Int) -> MachineProfile? }`. 소속 표시명은 Localization `factionName(_ key: String)` (efsf 지구연방군/Earth Federation/地球連邦軍, zeon 지온공국군/Principality of Zeon/ジオン公国軍, aeug 에우고/AEUG/エゥーゴ, titans 티탄즈/Titans/ティターンズ, axis 액시즈/Axis/アクシズ, neo_zeon 네오지온/Neo Zeon/ネオ・ジオン, londo_bell 론도벨/Londo Bell/ロンド・ベル; 모르는 키는 키 그대로).

- [ ] **Step 1: 실패하는 테스트** — `test_profileForSpecies()` (encode(2,.hg) → modelNumber "MS-06F", releasedGrades [sd,hg,rg,mg,pg]), `test_unknownSpeciesHasNoProfile()`.
- [ ] **Step 2: 실패 확인** — FAIL.
- [ ] **Step 3: 구현** — 상세 화면의 포켓몬 프로필 영역을 MachineProfile(형식번호, 소속, 등장 작품, 출시 등급 칩)로 교체. 개체 `profile` 관련 성장·마이그레이션 코드는 호출을 끊고 `profile == nil`에서 아무것도 안 하게(필드는 세이브 호환 위해 남김). `detailProvider` 경로 제거.
- [ ] **Step 4: 통과 확인** — `swift test 2>&1 | tail -20` / PASS.
- [ ] **Step 5: Commit** — `feat(gunpla): replace battle profile with machine profile`

---

### Task 8: 문구·언어 (ko/en/ja)

**Files:**
- Modify: `Core/CompanionModel.swift` (`AppLanguage` → `ko, en, ja`), `Core/Localization.swift`, `Core/KoreanParticle.swift`(그대로 사용), `UI/SettingsView.swift`(언어 선택)
- Test: `Tests/PokeTokenBarTests/Gunpla/GunplaCopyTests.swift`

**Interfaces:**
- Produces: `Localization.t(_ ko: String, _ en: String, _ ja: String) -> String` 3인자 오버로드(새·변경 문구는 이것만 사용). 기존 8인자 `t`는 남겨 두고 es…ru 인자는 무시(업스트림 병합용). `AppLanguage.systemDefault(for:)`는 ko/ja 외 전부 en. 저장된 언어가 es…ru면 en으로 디코딩.
- 용어표 (사용자에게 보이는 모든 문구에 적용):

| 원본 | ko | en | ja |
|---|---|---|---|
| 포켓몬 | 기체 | Mobile Suit | 機体 |
| 알 | 건프라 박스 | Kit Box | キットボックス |
| 부화 | 개봉 | Unbox | 開封 |
| 진화 | 등급 업 | Grade Up | グレードアップ |
| 졸업 | 완성 | Complete | 完成 |
| 도감 | 격납고 | Hangar | 格納庫 |
| 지역 | 작품 | Series | 作品 |
| 이로치/Shiny | 전용기 | Custom | 専用機 |
| 이상한 사탕 | 스펀지 사포 | Sanding Sponge | スポンジヤスリ |
| 언커먼 알 / 레어 알 | 언커먼 박스 / 레어 박스 | Uncommon Box / Rare Box | アンコモンボックス / レアボックス |
| 마스킹 테이프·먹선펜·도료 세트·에어브러시 | (그대로) | Masking Tape · Panel Line Pen · Paint Set · Airbrush | マスキングテープ · スミ入れペン · 塗料セット · エアブラシ |
| 등급 소진 안내 (`hangarTierComplete`) | 이 등급 이상은 모두 모았어요 | You've completed every kit at this tier or above | このランク以上はすべて集めました |

- [ ] **Step 1: 실패하는 테스트** — `test_onlyThreeLanguages()` (`AppLanguage.allCases == [.ko,.en,.ja]`), `test_legacyLanguageDecodesToEnglish()` ("de" → .en), `test_noPokemonWordsInVisibleCopy()` — `Localization`의 모든 공개 문자열 프로퍼티를 ko/en/ja로 렌더해 "포켓몬|Pokémon|ポケモン|Pokédex|도감|図鑑" 정규식이 0건(리플렉션이 어렵다면 대표 키 30개 목록으로).
- [ ] **Step 2: 실패 확인** — FAIL.
- [ ] **Step 3: 구현** — 용어표대로 교체. `KoreanParticle` 조사 처리는 새 이름에도 그대로 사용.
- [ ] **Step 4: 통과 확인** — PASS.
- [ ] **Step 5: Commit** — `feat(gunpla): gunpla terminology and ko/en/ja only`

---

### Task 9: 포켓몬 잔재 제거·최종 검증

**Files:**
- Delete: `Core/PokeAPIClient.swift`(단, `PokeProviding`·`PokemonDetailProviding`·`BaseSpecies` 선언은 `Gunpla/ProviderProtocols.swift`로 옮김), `Core/PokemonNameLocalization.swift`, 남은 포켓몬 전용 테스트(`PokemonNameLocalizationTests`, `DexNameMigrationTests` 중 PokeAPI 의존 부분 등)
- Modify: `PokemonForm` 참조 — 컴파일러가 허용하는 범위에서 제거하되, 세이브 디코딩에 필요한 최소 타입은 남긴다(완전 삭제가 Task 범위를 크게 넘으면 남기고 커밋 본문에 기록).

- [ ] **Step 1: 네트워크 잔재 확인** — Run: `grep -rn "pokeapi\|PokeAPI/sprites" Sources` / Expected: 0건.
- [ ] **Step 2: 전체 검증** — Run: `swift build -c release && swift test 2>&1 | tail -5 && PTB_NATIVE_ARCH_ONLY=1 scripts/build-app.sh` / Expected: 빌드 성공, 테스트 전부 통과, `.app` 생성.
- [ ] **Step 3: 수동 시나리오** — 새 Application Support 폴더로 앱 실행 → 박스 개봉 → 등급 업 2회(스펀지 사포 사용) → 새 박스 구매로 내보내기 → 격납고에 도달 등급 표시 → 상점에서 공구 순서 잠금 확인 → 설정에서 언어 ko/en/ja 전환. 원본 PokeTokenBar가 설치돼 있어도 세이브·로그 폴더가 섞이지 않는지 확인.
- [ ] **Step 4: Commit** — `chore(gunpla): remove remaining Pokémon data layer`
- [ ] **Step 5: 마무리** — superpowers:finishing-a-development-branch 로 `gunpla/app` 통합 방식 결정(포크 저장소 안 PR 또는 main 병합).
