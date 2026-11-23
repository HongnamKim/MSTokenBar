import XCTest
@testable import PokeTokenBar

final class GunplaCopyTests: XCTestCase {
    /// Words that must never reach the user in the Gunpla build.
    private static let forbidden = try! NSRegularExpression(
        pattern: "포켓몬|Pokémon|Pokemon|ポケモン|Pokédex|도감|図鑑|이로치|色違い|사탕|Rare Candy")

    private func hits(_ text: String) -> Bool {
        forbidden.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
    private var forbidden: NSRegularExpression { Self.forbidden }

    // MARK: languages

    func test_onlyThreeLanguages() {
        XCTAssertEqual(AppLanguage.allCases, [.ko, .en, .ja])
    }

    func test_legacyLanguageDecodesToEnglish() throws {
        let decoded = try JSONDecoder().decode([AppLanguage].self, from: Data(#"["de","es","fr","pt","ru","ko","ja"]"#.utf8))
        XCTAssertEqual(decoded, [.en, .en, .en, .en, .en, .ko, .ja])

        let state = try JSONDecoder().decode(CompanionState.self, from: Data(#"{"language":"de"}"#.utf8))
        XCTAssertEqual(state.language, .en)
    }

    func test_systemDefaultMapsOnlyKoAndJa() {
        XCTAssertEqual(AppLanguage.systemDefault(for: "ko-KR"), .ko)
        XCTAssertEqual(AppLanguage.systemDefault(for: "ja-JP"), .ja)
        for id in ["de-DE", "es-ES", "fr-FR", "pt-BR", "ru-RU", "en-US", nil] {
            XCTAssertEqual(AppLanguage.systemDefault(for: id), .en, id ?? "nil")
        }
    }

    func test_threeArgTReadsEnglishForEverythingButKoJa() {
        XCTAssertEqual(L(.ko).t("가", "a", "あ"), "가")
        XCTAssertEqual(L(.en).t("가", "a", "あ"), "a")
        XCTAssertEqual(L(.ja).t("가", "a", "あ"), "あ")
    }

    // MARK: terminology

    func test_noPokemonWordsInVisibleCopy() {
        let badges: [DexBadge] = [.series("zeta"), .seriesVariant("zeta"), .all, .allVariant]
        let tiers: [Rarity?] = [nil, .common, .uncommon, .rare, .legendary]
        for lang in AppLanguage.allCases {
            let l = L(lang)
            var rendered: [(String, String)] = [
                // tabs / segments / hangar
                ("collection", l.collection), ("hangarTitle", l.hangarTitle), ("dexTitle", l.dexTitle),
                ("catchLogTitle", l.catchLogTitle), ("dexTotal", l.dexTotal(3)),
                ("hangarMachineTotal", l.hangarMachineTotal(3)), ("hangarVariantLabel", l.hangarVariantLabel),
                ("dexEmptyTitle", l.dexEmptyTitle), ("dexEmptyHint", l.dexEmptyHint),
                ("dexShinyLabel", l.dexShinyLabel), ("dexSearchPlaceholder", l.dexSearchPlaceholder),
                ("dexOpenEntryHint", l.dexOpenEntryHint), ("filterShinyOnly", l.filterShinyOnly),
                ("noSearchResults", l.noSearchResults), ("sortDexNumberAsc", l.sortDexNumberAsc),
                ("sortDexNumberDesc", l.sortDexNumberDesc), ("hangarTierComplete", l.hangarTierComplete),
                // companion status
                ("finalForm", l.finalForm), ("stage", l.stage(1, 3)), ("unknownNextEvolution", l.unknownNextEvolution),
                ("eggIncubating", l.eggIncubating), ("eggToHatch", l.eggToHatch("1M")),
                ("eggHatchDelayed", l.eggHatchDelayed), ("toNextEvolution", l.toNextEvolution("1M")),
                ("toGraduation", l.toGraduation("1M")), ("graduated", l.graduated("RX-78-2")),
                ("statusEgg", l.statusEgg), ("statusEvolved", l.statusEvolved("Zeta")),
                ("eggImminent", l.eggImminent), ("eggFirstRunHint", l.eggFirstRunHint("5M")),
                ("evolutionScrollPrevious", l.evolutionScrollPrevious), ("evolutionScrollNext", l.evolutionScrollNext),
                ("recapGraduates", l.recapGraduates), ("recapNoGraduates", l.recapNoGraduates),
                // notifications
                ("notifHatchTitle", l.notifHatchTitle), ("notifHatchBody", l.notifHatchBody("RX-78-2")),
                ("notifShinyHatchTitle", l.notifShinyHatchTitle),
                ("notifShinyHatchBody", l.notifShinyHatchBody("RX-78-2", odds: 64)),
                ("notifEvolveTitle", l.notifEvolveTitle), ("notifEvolveBody", l.notifEvolveBody(from: "A", to: "B")),
                ("notifGraduateTitle", l.notifGraduateTitle), ("notifGraduateBody", l.notifGraduateBody("RX-78-2")),
                ("notifCandyTitle", l.notifCandyTitle(item: l.itemName(.rareCandy), count: 2)),
                ("notifCandyBody", l.notifCandyBody(window: "5h")),
                ("notifPrayerHatchBody.legendaryCustom", l.notifPrayerHatchBody("A", prayers: 90, shiny: true, rarity: .legendary)),
                ("notifPrayerHatchBody.legendary", l.notifPrayerHatchBody("A", prayers: 90, shiny: false, rarity: .legendary)),
                ("notifPrayerHatchBody.custom", l.notifPrayerHatchBody("A", prayers: 90, shiny: true, rarity: .rare)),
                ("notifPrayerHatchBody.common", l.notifPrayerHatchBody("A", prayers: 90, shiny: false, rarity: .common)),
                ("notifPrayerHatchBody.rare", l.notifPrayerHatchBody("A", prayers: 90, shiny: false, rarity: .rare)),
                // shop / bag
                ("useAfterHatch", l.useAfterHatch), ("useNeedsPokemon", l.useNeedsPokemon),
                ("candyGraduates", l.candyGraduates), ("candyCarryoverXP", l.candyCarryoverXP("1M")),
                ("candyDiscardedXP", l.candyDiscardedXP("1M")), ("eggShopLockedHint", l.eggShopLockedHint),
                ("eggReleaseNote", l.eggReleaseNote), ("eggConfirm", l.eggConfirm("A", "B")),
                ("freshEggShinyWarning", l.freshEggShinyWarning), ("freshEggLegendaryWarning", l.freshEggLegendaryWarning),
                ("freshEggDiscardShiny", l.freshEggDiscardShiny), ("freshEggDiscardValuable", l.freshEggDiscardValuable),
                ("toolEffectHint", l.toolEffectHint), ("toolLockedHint", l.toolLockedHint),
                // settings companions
                ("representativePokemonLabel", l.representativePokemonLabel),
                ("representativeFollowCurrent", l.representativeFollowCurrent),
                ("representativeChooseFromDex", l.representativeChooseFromDex),
                ("representativeSet", l.representativeSet),
                ("pokemonGrowthPercent", l.pokemonGrowthPercent), ("pokemonGrowthPercentHint", l.pokemonGrowthPercentHint),
                ("menuGrowthProgress.egg", l.menuGrowthProgress(10, isEgg: true)),
                ("menuGrowthProgress", l.menuGrowthProgress(10, isEgg: false)),
                ("companionNotificationsLabel", l.companionNotificationsLabel),
                ("trackedProvidersHint", l.trackedProvidersHint), ("exportSaveHint", l.exportSaveHint),
                ("floatingPetSectionTitle", l.floatingPetSectionTitle), ("floatingPetEnableLabel", l.floatingPetEnableLabel),
                ("floatingPetHint", l.floatingPetHint), ("floatingPetHideLabel", l.floatingPetHideLabel),
                ("floatingPetMenuHide", l.floatingPetMenuHide), ("floatingPetHeartsLabel", l.floatingPetHeartsLabel),
                ("allOffHint", l.allOffHint), ("statusSulk", l.statusSulk),
                ("importConfirmBody", l.importConfirmBody(incomingDex: 1, incomingTokens: "1M", exportedAt: "x",
                                                          sourceDevice: "y", currentDex: 2, currentTokens: "2M")),
                ("importSaveDone", l.importSaveDone(dex: 1, tokens: "1M")),
                ("restoreConfirmBody", l.restoreConfirmBody(snapshotDate: "x", snapshotDex: 1, snapshotTokens: "1M",
                                                            currentDex: 2, currentTokens: "2M")),
                ("restoreDoneMessage", l.restoreDoneMessage(dex: 1, tokens: "1M")),
                ("snapshotDexAndTokens", l.snapshotDexAndTokens(dex: 1, tokens: "1M")),
            ]
            for kind in ItemKind.allCases {
                rendered.append(("itemName.\(kind)", l.itemName(kind)))
                rendered.append(("itemDescription.\(kind)", l.itemDescription(kind)))
            }
            for tier in tiers {
                rendered.append(("eggName.\(String(describing: tier))", l.eggName(tier)))
                rendered.append(("eggDescription.\(String(describing: tier))", l.eggDescription(tier)))
            }
            for badge in badges {
                rendered.append(("dexBadgeLabel.\(badge)", l.dexBadgeLabel(badge, seriesName: "Zeta")))
                rendered.append(("notifHangarCompleteTitle.\(badge)", l.notifHangarCompleteTitle(badge, seriesName: "Zeta")))
                rendered.append(("notifHangarCompleteBody.\(badge)", l.notifHangarCompleteBody(badge, seriesName: "Zeta")))
            }
            for n in 0..<10 { rendered.append(("prayerQuip.\(n)", l.prayerQuip(n * 30))) }

            XCTAssertGreaterThanOrEqual(rendered.count, 30)
            for (key, text) in rendered {
                XCTAssertFalse(hits(text), "\(lang) \(key): \(text)")
                XCTAssertFalse(text.isEmpty, "\(lang) \(key) is empty")
            }
        }
    }

    /// Every string literal in Localization.swift, including keys the explicit list above does not call.
    func test_noPokemonWordsInLocalizationSourceLiterals() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/Core/Localization.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let literal = try NSRegularExpression(pattern: #""(?:\\.|[^"\\\n])*""#)
        var offenders: [String] = []
        for (index, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let range = NSRange(line.startIndex..., in: line)
            for match in literal.matches(in: line, range: range) {
                let text = (line as NSString).substring(with: match.range)
                if hits(text) { offenders.append("line \(index + 1): \(text)") }
            }
        }
        XCTAssertTrue(offenders.isEmpty, offenders.joined(separator: "\n"))
    }

    func test_terminologyTable() {
        XCTAssertEqual(L(.ko).eggName(nil), "건프라 박스")
        XCTAssertEqual(L(.en).eggName(nil), "Kit Box")
        XCTAssertEqual(L(.ja).eggName(nil), "キットボックス")
        XCTAssertEqual(L(.ko).eggName(.uncommon), "언커먼 박스")
        XCTAssertEqual(L(.en).eggName(.rare), "Rare Box")
        XCTAssertEqual(L(.ja).eggName(.rare), "レアボックス")
        XCTAssertEqual(L(.ko).itemName(.rareCandy), "스펀지 사포")
        XCTAssertEqual(L(.en).itemName(.rareCandy), "Sanding Sponge")
        XCTAssertEqual(L(.ja).itemName(.rareCandy), "スポンジヤスリ")
        XCTAssertEqual([L(.ko).dexTitle, L(.en).dexTitle, L(.ja).dexTitle], ["격납고", "Hangar", "格納庫"])
        XCTAssertEqual([L(.ko).catchLogTitle, L(.en).catchLogTitle, L(.ja).catchLogTitle], ["제작 기록", "Build Log", "製作記録"])
        XCTAssertEqual([L(.ko).dexShinyLabel, L(.en).dexShinyLabel, L(.ja).dexShinyLabel], ["전용기", "Custom", "専用機"])
        XCTAssertEqual([L(.ko).notifHatchTitle, L(.en).notifHatchTitle, L(.ja).notifHatchTitle],
                       ["개봉!", "Unboxed!", "開封！"])
        XCTAssertEqual([L(.ko).notifEvolveTitle, L(.en).notifEvolveTitle, L(.ja).notifEvolveTitle],
                       ["등급 업!", "Grade Up!", "グレードアップ！"])
        XCTAssertEqual([L(.ko).notifGraduateTitle, L(.en).notifGraduateTitle, L(.ja).notifGraduateTitle],
                       ["완성!", "Complete!", "完成！"])
    }

    func test_rareCandyGrantNotificationUsesTheSpongeItem() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            let title = l.notifCandyTitle(item: l.itemName(.rareCandy), count: 3)
            XCTAssertTrue(title.contains(l.itemName(.rareCandy)), title)
            XCTAssertTrue(title.contains("3"), title)
            XCTAssertFalse(title.contains("🍬"), title)
        }
        XCTAssertTrue(L(.ko).notifCandyBody(window: "5시간").contains("스펀지 사포"))
    }

    func test_hangarSearchPlaceholderMentionsModelNumberNotHashNumber() {
        XCTAssertEqual(L(.ko).dexSearchPlaceholder, "이름 또는 형식번호 검색…")
        XCTAssertEqual(L(.en).dexSearchPlaceholder, "Search name or model number…")
        XCTAssertEqual(L(.ja).dexSearchPlaceholder, "名前または型式番号で検索…")
    }

    func test_hangarMachineTotalPluralizesEnglish() {
        XCTAssertEqual(L(.en).hangarMachineTotal(1), "1 suit")
        XCTAssertEqual(L(.en).hangarMachineTotal(0), "0 suits")
        XCTAssertEqual(L(.en).hangarMachineTotal(2), "2 suits")
        XCTAssertEqual(L(.ko).hangarMachineTotal(1), "1기")
    }
}
