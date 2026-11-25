import Foundation

/// 표시 상태 — 사용량/burn 으로 결정(스프라이트 모션 강도·상태 문구).
/// `sulk`: no token usage for `PokemonBalance.sulkAfterIdle` — the companion turns its back.
enum CompanionStateKind: String, Sendable {
    case egg, idle, working, focus, tired, sleep, sulk, levelUp
}

/// 앱 언어. 기체 이름은 번들 카탈로그의 다국어 names 에서 가져온다. ko / en / ja 세 가지만 지원한다.
enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case ko, en, ja

    /// 저장된 값이 es/fr/pt/de/ru 처럼 더는 지원하지 않는 언어여도 디코딩은 실패하지 않고 영어가 된다.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AppLanguage(rawValue: raw) ?? .en
    }

    /// 이름 언어 코드 후보(첫 매칭 사용)
    var apiCodes: [String] {
        switch self {
        case .ko: return ["ko"]
        case .en: return ["en"]
        case .ja: return ["ja-hrkt", "ja"]
        }
    }
    var label: String {
        switch self { case .ko: return "한국어"; case .en: return "English"; case .ja: return "日本語" }
    }

    var displayLocale: Locale { Locale(identifier: rawValue) }

    /// byLang(langCode→name) 에서 이 언어의 이름을 고른다(apiCodes 첫 매칭 → 영어 폴백).
    func resolveName(_ byLang: [String: String]) -> String? {
        // Old saves may hold mixed-case or underscored language codes (for example ja-Hrkt).
        func code(_ raw: String) -> String {
            raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: "-")
        }
        var normalized: [String: String] = [:]
        for key in byLang.keys.sorted() {
            let value = byLang[key]!.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { normalized[code(key)] = value }
        }
        for preferred in apiCodes + ["en"] {
            if let name = normalized[code(preferred)] { return name }
        }
        return nil
    }

    /// 신규 설치 기본 언어 — 시스템 선호 언어에서 유추. ko/ja 만 매칭, 그 외 전부 영어.
    /// 기존 사용자는 저장된 언어를 그대로 쓴다.
    static var systemDefault: AppLanguage {
        systemDefault(for: Locale.preferredLanguages.first)
    }

    /// 시스템 언어 매핑의 순수 판정 — 실제 환경을 바꾸지 않고 locale 분기를 검증할 수 있게 분리한다.
    static func systemDefault(for preferredLanguage: String?) -> AppLanguage {
        switch preferredLanguage?.prefix(2).lowercased() {
        case "ko": return .ko
        case "ja": return .ja
        default:   return .en
        }
    }
}

/// 희귀도 — 기체 카탈로그의 rarity.
enum Rarity: String, Codable, Sendable {
    case common, uncommon, rare, legendary
    /// 등급 크기(높을수록 희귀) — 두 `Rarity` 를 비교하기 위한 순위.
    /// **목록 정렬용이 아니다**: 포획 로그는 기록 시각순, 도감은 도감 번호순이고 희귀도는 필터로만 좁힌다.
    /// 유일한 소비자는 프리미엄 알의 보증 관문(`hatch` 의 `line.rarity.sortRank < tier.sortRank`) —
    /// 뽑힌 등급이 산 보증보다 낮은지 판정한다. 순서가 뒤집히면 고급/희귀 알이 조용히 낮은 등급을
    /// 통과시키므로 `testSortRankOrdersRarityAscendingByValue` 가 순서를 고정한다.
    var sortRank: Int {
        switch self {
        case .common:    return 0
        case .uncommon:  return 1
        case .rare:      return 2
        case .legendary: return 3
        }
    }
    /// 이 등급의 capture_rate 상한 — 이 값 이하면 그 종은 이 등급 **이상**이다.
    /// `from(captureRate:…)` 의 분류 임계이자, 프리미엄 알이 부화 후보를 미리 거르는 기준이다.
    /// 두 곳에 임계를 따로 적으면 한쪽만 바뀌었을 때 등급 보증이 조용히 깨지므로 **여기가 단일 소스**다.
    ///
    /// nil = capture_rate 로 표현할 수 없는 등급. 전설은 `is_legendary`/`is_mythical` 로만 판정되는데
    /// 부화 후보 인덱스(`BaseSpecies`)에는 그 플래그가 없다 → 전설 **전용** 알은 만들 수 없다(팔지도 않는다).
    /// 반대로 전설은 전원 capture_rate ≤ 45 라 하한을 *위로만* 벗어나므로, 고급/희귀 알의 capture_rate
    /// 필터에는 자연스럽게 포함된다("고급 이상"·"희귀 이상" 규칙이 그대로 성립).
    var captureRateCeiling: Int? {
        switch self {
        case .rare:      return 45
        case .uncommon:  return 120
        case .common:    return 255
        case .legendary: return nil
        }
    }
    /// capture_rate 가 이 등급 이상을 뜻하는지 — 전설은 capture_rate 로 판정할 수 없어 항상 false.
    func includes(captureRate: Int) -> Bool {
        guard let ceiling = captureRateCeiling else { return false }
        return captureRate <= ceiling
    }
    static func from(captureRate: Int, isLegendary: Bool, isMythical: Bool) -> Rarity {
        if isLegendary || isMythical { return .legendary }
        if Rarity.rare.includes(captureRate: captureRate) { return .rare }
        if Rarity.uncommon.includes(captureRate: captureRate) { return .uncommon }
        return .common
    }
}

/// 토큰 경제 — 실측 평균(~253M/일) 기준.
/// 졸업 총량 T 는 같은 희귀도면 진화 단계 수와 무관하게 동일.
/// 형태 k개 라인에서 i번째 형태 성장 비용 = T·i / (k(k+1)/2) → 합 = T, 단계↑일수록 비용↑.
enum PokemonBalance {
    /// With no token usage for this long the companion turns its back (`CompanionStateKind.sulk`).
    static let sulkAfterIdle: TimeInterval = 3 * 3600
    /// 알 부화 임계 — 이만큼 토큰을 써야 알이 깨진다(즉시 부화 대신 기대감). 초과분은 부화체 성장에 이월.
    static let eggHatchThreshold = 5_000_000
    static let repeatGrowthMultiplier = 2

    static func graduationTotal(_ rarity: Rarity) -> Int {
        switch rarity {
        case .common:    return    750_000_000
        case .uncommon:  return  1_875_000_000
        case .rare:      return  3_000_000_000
        case .legendary: return  6_000_000_000
        }
    }
    /// stageIndex(0-based)에서 다음 단계/졸업까지 필요한 토큰.
    static func phaseThreshold(rarity: Rarity, totalForms k: Int, stageIndex: Int,
                               growthMultiplier: Int = 1) -> Int {
        let kk = max(1, k)
        let i = stageIndex + 1                         // 1-based
        let total = Double(graduationTotal(rarity))
        let denom = Double(kk * (kk + 1)) / 2.0
        let standardThreshold = Int((total * Double(i) / denom).rounded())
        return max(1, Int((Double(standardThreshold) / Double(max(1, growthMultiplier))).rounded()))
    }

    // MARK: 난이도 배율 (설정 슬라이더)

    /// 사용자 조절 배율의 허용 범위. 1 미만이면 기본보다 빠르고·싸며, 1 초과면 느리고·비싸다.
    static let difficultyRange: ClosedRange<Double> = 0.1...2.0
    /// 기본값 — 이 값에서 모든 밸런스가 위 상수표 그대로다(기존 동작과 동일).
    static let defaultDifficulty: Double = 1.0

    /// 저장값을 허용 범위로 조인다. UserDefaults 는 `defaults write` 로 외부에서 쓸 수 있어
    /// 0·음수·NaN 이 실제로 들어올 수 있고, 배율 0 은 임계 0(진행률 0 나눗셈·퇴화한 진화 루프)이 된다.
    static func clampDifficulty(_ value: Double) -> Double {
        guard value.isFinite else { return defaultDifficulty }
        return min(max(value, difficultyRange.lowerBound), difficultyRange.upperBound)
    }

    /// 기본값 × 난이도 — 임계·가격 공통. **상수표 자체는 스케일하지 않는다**: 등급 알 가격이
    /// `graduationTotal` 의 *비율*로 파생되므로(FreshEgg.price), 표를 건드리면 성장 배율이 상점
    /// 가격까지 끌고 간다. 소비 지점에서만 곱해 두 배율을 서로 독립으로 유지한다.
    static func scaled(_ base: Int, by difficulty: Double) -> Int {
        Int((Double(base) * clampDifficulty(difficulty)).rounded())
    }

    // MARK: 슬라이더 위치 ↔ 배율 (로그 매핑)
    // 같은 비율의 변화가 같은 거리를 차지한다. 기본값은 트랙의 ±1%에서 스냅한다.
    private static let defaultSnapWidth = 0.01

    /// 슬라이더 위치(0…1) → 배율.
    static func difficulty(atPosition position: Double) -> Double {
        let lo = difficultyRange.lowerBound, hi = difficultyRange.upperBound
        let p = min(max(position, 0), 1)
        if abs(p - difficultyPosition(defaultDifficulty)) < defaultSnapWidth { return defaultDifficulty }
        return snapDifficulty(lo * pow(hi / lo, p))
    }

    /// 배율 → 슬라이더 위치(0…1).
    static func difficultyPosition(_ value: Double) -> Double {
        let lo = difficultyRange.lowerBound, hi = difficultyRange.upperBound
        return log(clampDifficulty(value) / lo) / log(hi / lo)
    }

    /// 로그 슬라이더에서 나온 값을 유효숫자 2자리로 정리한다 — 없으면 1.0473 같은 값이 그대로 표시된다.
    /// 기본값 되돌리기는 여기가 아니라 `difficulty(atPosition:)` 의 위치 스냅이 담당한다.
    static func snapDifficulty(_ value: Double) -> Double {
        guard value > 0 else { return difficultyRange.lowerBound }
        let magnitude = pow(10, (log10(value)).rounded(.down) - 1)
        return ((value / magnitude).rounded() * magnitude)
    }
}

/// 인벤토리 아이템 종류 — rawValue 로 CompanionState.inventory 에 저장. `rareCandy` 는 저장 호환을 위해 이름을
/// 유지한 채 스펀지 사포로 표시된다. 공구 4종은 보유형(패시브)이며 `ToolSet.order` 순서로만 산다.
/// case 선언 순서가 곧 상점 표시 순서다(`CompanionStore.purchasableItems`).
enum ItemKind: String, Codable, Sendable, CaseIterable {
    case rareCandy
    case maskingTape
    case panelLinePen
    case paintSet
    case airbrush

    /// 상점 판매가(재화 = 사용한 토큰). nil = 상점 미판매.
    var shopPrice: Int? {
        switch self {
        case .rareCandy: return RareCandy.price
        case .maskingTape, .panelLinePen, .paintSet, .airbrush: return ToolSet.prices[self]
        }
    }
    /// 보유형(패시브) 아이템 — 소비하지 않고 보유하는 동안 상시 효과. 1회 구매(재구매 불가), 가방엔 "적용 중" 표시.
    var isPassive: Bool {
        switch self {
        case .rareCandy: return false
        case .maskingTape, .panelLinePen, .paintSet, .airbrush: return true
        }
    }
}

/// 이상한 사탕 밸런스 상수.
enum RareCandy {
    /// 사용 시 현재 포켓몬에 주입하는 XP(토큰 환산). 2× 성장의 최소 임계는 62.5M 이지만,
    /// 기본 난이도·첫 부화에서는 초과 이월(<100M)이 다음 임계(125M)보다 작아 최대 1단계만 올린다.
    /// 낮은 난이도나 반복 부화 보너스에서는 여러 단계를 진행할 수 있다.
    static let xp = 100_000_000
    /// 주간 한도 100% 도달 시 지급 개수(세션급은 1개).
    static let weeklyGrant = 5
    /// 상점 구매가(재화 = 사용한 토큰: usedSinceInstall − spentTokens). XP 값어치(100M)의 5배.
    /// 토큰이 "성장 미터 + 상점 지갑"으로 이중 사용되는 구조라, 가격을 XP 와 같게 두면 구매가 사실상
    /// 공짜 추가성장(150M 써서 250M 성장)이 된다. 500M 로 두면 그 값 모으는 500M 패시브 성장 + 사탕
    /// 100M = 실질 보너스 +20% 로 억제된다. 무료 획득(한도 100% 보상)이 항상 이득이도록 값어치보다 비싸게.
    static let price = 500_000_000
}

/// 새 알(리롤) 밸런스 상수 — 상점 구매 시 현재 포켓몬을 폐기하고 새 알로 되돌린다.
enum FreshEgg {
    /// 상점 구매가. 마음에 안 드는 부화를 리롤하는 프리미엄(쌓인 토큰의 활용처). 폐기 개체는 졸업이
    /// 아니라 그냥 사라지므로 도감·확률(collectedFinals)에 무영향 — "뽑은 적 없던 것처럼". 새 알은
    /// 처음부터 재인큐베이션(5M) 필요 + 성장(usedAtStage) 소멸이라 스팸/파밍이 자연 억제된다.
    static let price = 1_000_000_000

    /// 상점에서 파는 알 — 보증 없음(기본) → 고급 이상 → 희귀 이상. `nil` = 등급 보증 없는 기존 알.
    /// **전설 전용 알은 팔지 않는다**(등급 하한을 capture_rate 로 표현할 수 없고, 최고 등급을 확정
    /// 상품으로 만들지 않는다). 전설은 고급/희귀 알에서 자연 가중대로 섞여 나온다 — 희귀 알 기준 약 10%.
    static let shopTiers: [Rarity?] = [nil, .uncommon, .rare]

    /// 등급 보증 알의 가격 — 배율은 새 상수를 짓지 않고 **기존 졸업 총량 표**를 그대로 쓴다
    /// (common 750M : uncommon 1.875B : rare 3B = 1 : 2.5 : 4 → 1B / 2.5B / 4B).
    ///
    /// 확률 배율(고급 7.16% : 희귀 6.98% ≈ 1 : 2.03)로 매기면 안 된다 — 그러면 같은 값으로 고급 알
    /// 2개를 사는 쪽이 희귀+ 기대 1.039마리·전설 0.104마리로 희귀 알 1개(1.000·0.100)를 모든 축에서
    /// 앞질러 상위 티어가 완전 열등재가 된다. 졸업량 배율이라야 상위 티어가 희귀+ 1마리당 4.00B 로
    /// 하위 반복 구매(4.81B)보다 싸다.
    static func price(guaranteeing tier: Rarity?) -> Int {
        guard let tier else { return price }
        let multiplier = Double(PokemonBalance.graduationTotal(tier)) / Double(PokemonBalance.graduationTotal(.common))
        return Int((Double(price) * multiplier).rounded())
    }
}

/// 상점 표시 한 줄 — 판매 아이템(ItemKind) 또는 알 리롤(즉시 액션이라 ItemKind 가 아님).
/// `egg` 의 연관값은 **보증 등급 하한**(nil = 보증 없는 기존 알).
/// CompanionStore.shopEntries 가 이 둘을 카테고리 순서(아이템 → 알)로 이어 뷰가 단일 목록으로 그린다.
enum ShopEntry: Hashable, Sendable {
    case item(ItemKind)
    case egg(Rarity?)

    var price: Int {
        switch self {
        case .item(let kind): return kind.shopPrice ?? 0
        case .egg(let tier): return FreshEgg.price(guaranteeing: tier)
        }
    }
}

/// 사탕 지급 대상 한도 창의 분류 — session=1개·weekly=weeklyGrant.
enum WindowClass: Sendable { case session, weekly }

/// 사탕 지급 판정 입력 — 프로바이더 무관 한도 창 1개. (UsageStore.candyEligibleWindows 가 생성)
struct CandyWindow: Sendable {
    let key: String          // 안정 식별자(tier 추적) — resets_at 등 휘발 필드는 key 에 넣지 않는다
    let name: String         // 표시용(알림 "왜 받는지")
    let kind: WindowClass    // session=1개 · weekly=5개
    let utilization: Double  // 0~100+
    /// 창 epoch (`resets_at` / reset unix). key 는 안정, epoch 가 바뀌면 새 창 → 재무장(#326).
    /// nil 이면 100% 미만 관측으로만 재무장한다(Codex — credits 로 100% 를 넘겨 쓴다).
    let epoch: String?

    init(key: String, name: String, kind: WindowClass, utilization: Double, epoch: String? = nil) {
        self.key = key
        self.name = name
        self.kind = kind
        self.utilization = utilization
        self.epoch = epoch
    }
}

/// 사탕 지급 1건(순수 판정 결과) — 부수효과(인벤토리·알림)와 분리해 테스트 가능하게.
struct CandyGrant: Equatable, Sendable {
    let windowKey: String
    let windowName: String   // 알림 "왜 받는지"
    let count: Int
}

/// 현재 서비스가 제공하는 움직이는 포켓몬 스프라이트 범위.
/// 번들 밖 id 의 애니메이션 가능 범위(전국도감 #1...649)와 건프라 id.
enum PokemonAssets {
    static let animatedSpeciesIDs = 1...649

    static func hasAnimatedSprite(speciesID: Int) -> Bool {
        animatedSpeciesIDs.contains(speciesID) || GunplaID.isGunpla(speciesID)   // Gunpla ids bypass the GIF-asset filter
    }
}

/// 진화 라인 트리. 분기(evolves_to 다수)를 children 으로.
struct EvoNode: Codable, Sendable {
    let speciesID: Int
    let children: [EvoNode]

    /// 최장 경로 길이(형태 수). 분기는 보통 같은 깊이라 대표값으로 사용.
    var depth: Int { 1 + (children.map(\.depth).max() ?? 0) }
    func node(withID id: Int) -> EvoNode? {
        if speciesID == id { return self }
        for c in children { if let f = c.node(withID: id) { return f } }
        return nil
    }
    /// 이 노드에서 도달 가능한 모든 최종체 id
    var finalIDs: [Int] {
        children.isEmpty ? [speciesID] : children.flatMap(\.finalIDs)
    }
    /// 이 노드 아래의 모든 단계 id (자신 제외)
    var descendantIDs: [Int] { children.flatMap { [$0.speciesID] + $0.descendantIDs } }
    /// 이 노드 아래에서 찾은 단계 (자신 제외)
    func descendant(withID id: Int) -> EvoNode? {
        for c in children { if let f = c.node(withID: id) { return f } }
        return nil
    }

    /// 서비스에 GIF 에셋이 있는 종만 남긴 진화 트리. 지원하지 않는 종부터 그 하위 체인도 제외한다.
    func keepingAnimatedSprites() -> EvoNode? {
        guard PokemonAssets.hasAnimatedSprite(speciesID: speciesID) else { return nil }
        return EvoNode(speciesID: speciesID, children: children.compactMap { $0.keepingAnimatedSprites() })
    }
}

enum EvoLineItemContent: Equatable, Sendable {
    case species(Int)
    case mystery
}

enum EvoLineItemState: Equatable, Sendable {
    case done
    case current
    case future
}

struct EvoLineItem: Equatable, Sendable {
    let content: EvoLineItemContent
    let state: EvoLineItemState

    init(_ content: EvoLineItemContent, _ state: EvoLineItemState) {
        self.content = content
        self.state = state
    }
}

/// 부화 시 확정되는 라인 정보(트리 + 희귀도 + 다국어 이름).
struct EvoLine: Sendable {
    let baseID: Int
    let tree: EvoNode
    let rarity: Rarity
    /// speciesID → (langCode → name)
    let names: [Int: [String: String]]
    var totalForms: Int { tree.depth }

    init(baseID: Int, tree: EvoNode, rarity: Rarity, names: [Int: [String: String]]) {
        self.baseID = baseID
        self.tree = tree.keepingAnimatedSprites() ?? EvoNode(speciesID: baseID, children: [])
        self.rarity = rarity
        self.names = names
    }

    func localizedName(_ id: Int, _ lang: AppLanguage) -> String {
        lang.resolveName(names[id] ?? [:]) ?? "#\(id)"   // 폴백 순서는 AppLanguage.resolveName 단일 소스
    }
}

/// Prayers said over an egg, carried onto the individual that hatched from it.
/// Purely cosmetic: no roll (species, rarity, shiny) ever reads it.
struct PrayerRecord: Codable, Sendable, Equatable {
    var count: Int
}

/// 현재 키우는 포켓몬.
struct MonState: Codable, Sendable {
    var baseID: Int
    var pathIDs: [Int]      // 실제 진화 경로(분기 선택 반영)
    var plannedPathIDs: [Int] // 사전에 선택한 전체 진화 경로
    var stageIndex: Int     // pathIDs 내 현재 위치
    var usedAtStage: Int    // 현재 형태에서 누적 사용량
    var rarity: Rarity
    var totalForms: Int
    var isShiny = false             // 부화 시 확정, 진화해도 유지
    var hasGrowthBoost = false
    /// Prayers said over the egg this individual hatched from. Nil = none (and every pre-prayer save).
    var prayers: PrayerRecord?
    /// 화면에 이로치(전용기)로 보여도 되는가. 표시 경로는 전부 이것만 쓴다.
    var displaysShiny: Bool { isShiny }
    // pathIDs 가 비면(손상된 상태 파일) baseID 로 폴백 — 렌더마다 읽히므로 out-of-bounds 크래시 방지.
    var currentID: Int { pathIDs.isEmpty ? baseID : pathIDs[min(stageIndex, pathIDs.count - 1)] }
    /// 이번 육성 계획의 마지막 단계에 와 있는가. 계획은 최종 등급 전에 끝날 수 있다(빈 등급 칸만 채우는 재등장).
    var isAtPlanEnd: Bool { stageIndex >= plannedPathIDs.count - 1 }
    /// Base (difficulty-free) cost of the current stage. A Gunpla machine is priced on its FULL
    /// released-grade path — k = `machine.grades.count`, stage = the current grade's position there — so
    /// resuming at grade G costs exactly the remaining stages of an original run. Ids the catalog does not
    /// know keep the path-relative pricing.
    func phaseThreshold(catalog: MachineCatalog) -> Int {
        var k = totalForms, stage = stageIndex
        // From the start grade, not `currentID`: callers price future stages by moving `stageIndex` alone.
        if let decoded = GunplaID.decode(baseID),
           let machine = catalog.machine(id: decoded.machineID),
           let start = machine.grades.firstIndex(of: decoded.grade) {
            k = machine.grades.count
            // The stage's own grade where the plan names it: a run can skip a grade released after it passed.
            let planned = plannedPathIDs.indices.contains(stageIndex)
                ? GunplaID.decode(plannedPathIDs[stageIndex])?.grade : nil
            stage = planned.flatMap(machine.grades.firstIndex(of:)) ?? min(start + stageIndex, k - 1)
        }
        return PokemonBalance.phaseThreshold(
            rarity: rarity,
            totalForms: k,
            stageIndex: stage,
            growthMultiplier: hasGrowthBoost ? PokemonBalance.repeatGrowthMultiplier : 1)
    }

    init(baseID: Int, pathIDs: [Int], plannedPathIDs: [Int]? = nil, stageIndex: Int, usedAtStage: Int,
         rarity: Rarity, totalForms: Int, isShiny: Bool = false,
         hasGrowthBoost: Bool = false,
         prayers: PrayerRecord? = nil) {
        self.baseID = baseID
        self.pathIDs = pathIDs
        if let plannedPathIDs, !plannedPathIDs.isEmpty {
            self.plannedPathIDs = plannedPathIDs
        } else {
            self.plannedPathIDs = pathIDs
        }
        self.stageIndex = stageIndex
        self.usedAtStage = usedAtStage
        self.rarity = rarity
        self.totalForms = totalForms
        self.isShiny = isShiny
        self.hasGrowthBoost = hasGrowthBoost
        self.prayers = prayers
    }

    // 하위호환 디코딩: 구버전 저장에 없는 부화 속성은 기본값.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseID = try c.decode(Int.self, forKey: .baseID)
        pathIDs = try c.decode([Int].self, forKey: .pathIDs)
        // 빈 pathIDs 는 손상 상태 → 디코드 실패시켜 전체 CompanionState 가 기본(알)로 폴백되게 한다.
        guard !pathIDs.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .pathIDs, in: c, debugDescription: "empty pathIDs")
        }
        if let savedPlan = try c.decodeIfPresent([Int].self, forKey: .plannedPathIDs), !savedPlan.isEmpty {
            plannedPathIDs = savedPlan
        } else {
            plannedPathIDs = pathIDs
        }
        let decodedStageIndex = try c.decode(Int.self, forKey: .stageIndex)
        stageIndex = min(max(0, decodedStageIndex), pathIDs.count - 1)
        usedAtStage = try c.decode(Int.self, forKey: .usedAtStage)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        totalForms = try c.decode(Int.self, forKey: .totalForms)
        isShiny = try c.decodeIfPresent(Bool.self, forKey: .isShiny) ?? false
        hasGrowthBoost = try c.decodeIfPresent(Bool.self, forKey: .hasGrowthBoost) ?? false
        prayers = (try? c.decodeIfPresent(PrayerRecord.self, forKey: .prayers)) ?? nil
    }
}

/// 도감 항목 — 라인 전체(초기→최종) 순서 보존.
struct DexEntry: Codable, Sendable, Identifiable {
    /// Version 1 preserves every API language; earlier saves retained only app-supported names.
    static let currentNamesVersion = 1
    var id = UUID().uuidString
    var baseID: Int
    var finalID: Int
    var chainOrder: [Int]   // 초기→최종 종 id
    var rarity: Rarity
    var caughtAt: Date?
    var isShiny = false
    /// Prayers said over the egg this individual hatched from. Nil = none (and every pre-prayer save).
    var prayers: PrayerRecord?
    /// 진화 체인 각 종의 다국어 이름(speciesID → langCode → name). 졸업 시 로드된 라인에서 저장 →
    /// 도감의 단계별 스프라이트 밑 이름 표시가 네트워크 없이 즉시 + 언어 전환 대응. 구버전 저장분엔
    /// 없어(nil) 뷰가 line fetch 로 조회 후 백필한다.
    var names: [Int: [String: String]]?
    var namesVersion: Int?
    var needsNamesRefresh: Bool {
        namesVersion != Self.currentNamesVersion
            || chainOrder.contains { names?[$0]?.isEmpty != false }
    }
    /// 놓아준 시각 — 알을 새로 사서 육성을 포기한 기록. nil = 졸업분(구버전 저장분 포함).
    ///
    /// 두 기록을 한 배열에 두는 이유: 도감(`dexSpecies`)은 종이 어떻게 확보됐는지와 무관하게
    /// **보유 종**을 접는다. 놓아준 개체를 여기 넣지 않으면 그 종이 도감에서 사라진다 —
    /// 수집 화면이 "쌓이기만 한다"는 약속을 깨는 유일한 경로였다.
    var releasedAt: Date?
    /// 졸업이 아니라 놓아준 기록인가 — 포획 로그가 뱃지를 가르는 판정.
    var isReleased: Bool { releasedAt != nil }

    init(id: String = UUID().uuidString,
         baseID: Int, finalID: Int, chainOrder: [Int], rarity: Rarity,
         caughtAt: Date?, isShiny: Bool = false,
         names: [Int: [String: String]]? = nil, releasedAt: Date? = nil,
         prayers: PrayerRecord? = nil) {
        self.id = id
        self.baseID = baseID
        self.finalID = finalID
        self.chainOrder = chainOrder
        self.rarity = rarity
        self.caughtAt = caughtAt
        self.isShiny = isShiny
        self.names = names
        self.namesVersion = chainOrder.allSatisfy { names?[$0]?.isEmpty == false }
            ? Self.currentNamesVersion : nil
        self.releasedAt = releasedAt
        self.prayers = prayers
    }

    // 하위호환 디코딩 (MonState 와 동일 이유).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        baseID = try c.decode(Int.self, forKey: .baseID)
        finalID = try c.decode(Int.self, forKey: .finalID)
        chainOrder = try c.decode([Int].self, forKey: .chainOrder)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        caughtAt = try c.decodeIfPresent(Date.self, forKey: .caughtAt)
        isShiny = try c.decodeIfPresent(Bool.self, forKey: .isShiny) ?? false
        prayers = (try? c.decodeIfPresent(PrayerRecord.self, forKey: .prayers)) ?? nil
        // try? — 구버전(최종체 단일 [String:String]) 형식이 남아 있어도 종별 맵 디코딩 실패 시 nil 로
        // 강등(항목 전체 로드는 유지). 뷰가 line 조회로 백필한다.
        names = (try? c.decodeIfPresent([Int: [String: String]].self, forKey: .names)) ?? nil
        namesVersion = try? c.decodeIfPresent(Int.self, forKey: .namesVersion)
        // 이 필드 이전에 저장된 항목은 전부 졸업분이다 — nil 이 곧 "졸업"이라 마이그레이션이 필요 없다.
        releasedAt = try c.decodeIfPresent(Date.self, forKey: .releasedAt)
    }
}

/// 배열 항목별 격리 디코딩 래퍼 — 손상된 한 항목이 배열 전체(및 상위 상태) 디코드를 실패시키지 않게.
/// 각 항목을 `try?` 로 감싸므로 실패 항목은 `value == nil` 이 되고 배열 디코드 자체는 성공한다.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(T.self) }
}

private extension KeyedDecodingContainer {
    /// 관대 디코드 — 키 없음/null/타입 불일치를 모두 기본값으로 흡수한다. 한 필드 손상이 상태 전체
    /// (도감·인벤토리)를 날리지 않게(부분 복원 > 전면 리셋). 최상위가 JSON 객체가 아닌 전면 손상은 여전히 throw.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key, default def: T) -> T {
        (try? decode(type, forKey: key)) ?? def
    }
    func lenientOptional<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decode(type, forKey: key)
    }
}

/// 영속 상태(Application Support JSON). 포켓몬 전환 — 이전 커스텀 캐릭터 상태는 폐기(새로 시작).
struct CompanionState: Codable, Sendable {
    // 토큰: 설치 이후만 측정
    var installBaselineSet = false
    var usedSinceInstall = 0
    // 상점에서 쓴 토큰 누적(재화 지출 원장). 쓸 수 있는 재화 = usedSinceInstall − spentTokens.
    // 성장 미터(usedSinceInstall)는 불변 — 구매는 이 값만 올려 잔액을 깎는다(성장 되감김 없음).
    var spentTokens = 0
    // 현재 알이 생긴 뒤 쓴 토큰(부화 인큐베이션). 누적(usedSinceInstall)과 별개 — 졸업 후 새 알마다 0.
    var eggUsage = 0
    // 현재 알이 보증하는 등급 하한(프리미엄 알). nil = 보증 없음(무료 알·기본 알).
    // ★영속이어야 한다 — 구매 시점엔 종을 못 정한다(롤에 네트워크가 필요). 보증을 상태에 적어 두고
    // 롤이 그것을 읽어야 오프라인·재시작을 건너서도 산 것을 받는다. 부화·졸업 때 nil 로 소비된다.
    var eggTier: Rarity?
    // 알 상태에서 미리 롤해둔 부화 종(프리패칭) — 부화 순간 네트워크 딜레이 제거. 재시작에도 유지.
    var pendingHatchID: Int?
    /// Prayers said over the current egg (nil until the first one). Egg-scoped like `eggUsage`:
    /// reset by `resetEggPrayers` whenever a new egg starts and copied onto the hatched individual.
    var eggPrayers: PrayerRecord?
    /// 오늘 사용량 적립 기준값 — 프로바이더별로 독립 관리한다.
    ///
    /// `nil`은 aggregate `claimedTodayTokens`만 가지고 있던 구버전 세이브가 아직 첫 유효
    /// snapshot을 기준으로 seed되지 않았다는 뜻이다. 첫 update에서 현재 프로바이더 값을
    /// 기준값으로만 저장하고, 과거 사용량은 소급 지급하지 않는다. 빈 map은 이미 seed된 뒤
    /// 오늘 보고한 프로바이더가 없는 정상 상태와 구분되어야 하므로 `nil`과 별도로 유지한다.
    /// 키는 `UsageProvider.id`를 그대로 사용한다.
    var claimedTodayTokensByProvider: [String: Int]? = nil
    var lastDate = ""
    // 현재 포켓몬(없으면 알)
    var active: MonState?
    // 두 번째 플로팅 펫에 함께 띄울 기체(등급 종 id). 메뉴바와 첫 플로팅 펫은 항상 키우는 기체를 그린다.
    // 종 단위 선택이라 성격 같은 개체 정보는 들고 있지 않는다. 선택 가능한 범위는 격납고와 동일하게
    // 졸업분 + 현재 개체의 도달 단계이며, 그 범위에서 빠지면 reconcileRepresentativeSelection 이 nil 로 복구한다.
    var representativeSpeciesID: Int? = nil
    // 고른 기체를 두 번째 플로팅 펫으로 띄울지. 고른 기체가 없으면 켜져 있어도 아무것도 띄우지 않는다.
    var showsDisplayPet = false
    // 도감
    var dex: [DexEntry] = []
    // 소유한 (base,final) 쌍 — 분기 다양성용
    var collectedFinals: Set<String> = []
    var language: AppLanguage = .systemDefault   // 신규 설치 = 시스템 로케일
    // 인벤토리 (ItemKind.rawValue → 개수)
    var inventory: [String: Int] = [:]
    // 사탕 지급 엣지 상태(창 key → 지급한 tier). ★영속 — notifiedTier(인메모리)와 달리 재시작 무한지급 방지.
    var candyGrantTier: [String: Int] = [:]
    // 창 key → 마지막으로 본 epoch(`resets_at`). util 이 계속 100%여도 epoch 교체로 재무장(#326).
    var candyWindowEpoch: [String: String] = [:]
    // 사탕 지급 첫 실행 시드 완료 — 업데이트 직후 이미 100%였던 창의 소급 지급 차단.
    var candyFeatureSeeded = false
    // 세대(지역) 도감 완성 알림을 이미 보낸 배지 키. 재시작마다 다시 알리지 않게 영속.
    var notifiedDexCompletions: Set<String> = []
    // 완성 추적 첫 실행 시드 완료 — 기능 출시 전 이미 완성한 세대에 알림 폭주를 막는다(candyFeatureSeeded 패턴).
    var dexCompletionsSeeded = false

    init() {}

    // 하위호환 + 손상 복원 디코딩: 누락 키·타입 불일치·일부 손상 필드를 모두 기본값으로 흡수한다 —
    // 한 필드가 깨져도 상태 전체(도감·인벤토리)를 날리지 않는다(부분 복원). 최상위가 JSON 객체가 아닌
    // 전면 손상만 throw → load() 가 원본을 .corrupt 로 백업하고 fresh 로 시작.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        installBaselineSet = c.lenient(Bool.self, forKey: .installBaselineSet, default: false)
        usedSinceInstall   = c.lenient(Int.self, forKey: .usedSinceInstall, default: 0)
        spentTokens        = c.lenient(Int.self, forKey: .spentTokens, default: 0)
        eggUsage           = c.lenient(Int.self, forKey: .eggUsage, default: 0)
        // 모르는 rawValue 는 nil(보증 없음)로 강등 — 관대 디코딩의 안전한 방향(있지도 않은 보증을 만들지 않는다).
        eggTier            = c.lenientOptional(Rarity.self, forKey: .eggTier)
        pendingHatchID     = c.lenientOptional(Int.self, forKey: .pendingHatchID)
        eggPrayers         = c.lenientOptional(PrayerRecord.self, forKey: .eggPrayers)
        if c.contains(.claimedTodayTokensByProvider) {
            claimedTodayTokensByProvider = c.lenient([String: Int].self,
                                                      forKey: .claimedTodayTokensByProvider,
                                                      default: [:])
        } else {
            // 구버전의 aggregate claimedTodayTokens 키는 의도적으로 읽지 않는다. 프로바이더별
            // 분해가 불가능하므로 다음 CompanionStore.update에서 현재 snapshot을 기준점으로 seed한다.
            claimedTodayTokensByProvider = nil
        }
        lastDate           = c.lenient(String.self, forKey: .lastDate, default: "")
        // active 손상(빈 pathIDs 등) → 알로 폴백하되 도감·인벤토리는 보존.
        active             = c.lenientOptional(MonState.self, forKey: .active)
        representativeSpeciesID = c.lenientOptional(Int.self, forKey: .representativeSpeciesID)
        // Before this key, a chosen machine replaced the raised one everywhere; keep it on screen as the second pet.
        showsDisplayPet    = c.lenient(Bool.self, forKey: .showsDisplayPet, default: representativeSpeciesID != nil)
        // 도감은 항목별 격리 — 손상 항목 하나가 도감 전체를 날리지 않게.
        dex                = c.lenient([Lossy<DexEntry>].self, forKey: .dex, default: []).compactMap(\.value)
        collectedFinals    = c.lenient(Set<String>.self, forKey: .collectedFinals, default: [])
        language           = c.lenient(AppLanguage.self, forKey: .language, default: .systemDefault)
        inventory          = c.lenient([String: Int].self, forKey: .inventory, default: [:])
        candyGrantTier     = c.lenient([String: Int].self, forKey: .candyGrantTier, default: [:])
        candyWindowEpoch   = c.lenient([String: String].self, forKey: .candyWindowEpoch, default: [:])
        candyFeatureSeeded = c.lenient(Bool.self, forKey: .candyFeatureSeeded, default: false)
        notifiedDexCompletions = c.lenient(Set<String>.self, forKey: .notifiedDexCompletions, default: [])
        dexCompletionsSeeded = c.lenient(Bool.self, forKey: .dexCompletionsSeeded, default: false)
    }

    /// 졸업 기록 또는 현재 개체가 실제로 도달한 단계에 이 종이 포함되는가.
    /// 도감 전체 표시 모델을 만들지 않고 대표 종 하나만 확인하는 경량 경로다.
    func ownsSpecies(_ speciesID: Int) -> Bool {
        if dex.contains(where: { $0.chainOrder.contains(speciesID) }) { return true }
        guard let active else { return false }
        return active.pathIDs.prefix(active.stageIndex + 1).contains(speciesID)
    }

    /// 보유한 특정 종의 이로치(전용기) 여부. 졸업 기록과 현재 도달 단계만 훑으며 이름·정렬·희귀도 등
    /// 도감 표시 모델은 계산하지 않는다.
    func ownsShinySpecies(_ speciesID: Int) -> Bool {
        if dex.contains(where: { $0.isShiny && $0.chainOrder.contains(speciesID) }) { return true }
        guard let active, active.pathIDs.prefix(active.stageIndex + 1).contains(speciesID) else { return false }
        return active.displaysShiny
    }

    /// Forget the prayers of the previous egg. Call on every path that starts a new egg (or consumes this one).
    mutating func resetEggPrayers() { eggPrayers = nil }

    /// 대표 포켓몬은 사용자가 현재 보유한 종만 가리킨다. Fresh Egg·손편집 세이브가
    /// 유령 종을 메뉴바와 플로팅 펫에 영구히 남기지 않게 한다.
    mutating func reconcileRepresentativeSelection() {
        guard let selected = representativeSpeciesID else { return }
        if !ownsSpecies(selected) { representativeSpeciesID = nil }
    }
}
