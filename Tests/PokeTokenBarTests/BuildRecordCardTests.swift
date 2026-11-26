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
        let endUnknown = try build([.sd, .mgsd, .hg, .rg, .mg],
                                   [142_900_000, 285_700_000, 428_600_000, 571_400_000, 982_100_000],
                                   openedAt: t0)

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
        XCTAssertEqual(header(endUnknown, .ko, now: day(30)), "개봉 \(date(t0, .ko)) · 총 2.41B")
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

    /// The card sits on the detail page only when the selected build has a record. The page is a
    /// scroll view, so the card shows up as extra document height.
    func test_detailPageShowsTheCardOnlyForABuildWithARecord() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("build-record-card-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = ProcessInfo.processInfo.environment["PTB_BUILD_RECORD_RENDER_DIR"].map(URL.init(fileURLWithPath:))
        let machine = try XCTUnwrap(MachineCatalog.allBundled.machine(id: 1))
        let chain = machine.grades.map { GunplaID.encode(machineID: 1, grade: $0) }
        let record = BuildLog(openedAt: t0, stages: chain.enumerated().map { offset, species in
            BuildStage(speciesID: species, reachedAt: day(offset * 3),
                       tokensByProvider: ["claude": 150_000_000 * (offset + 1), "codex": 40_000_000],
                       sandpaper: offset == 1 ? 100_000_000 : 0, unattributed: offset == 0 ? 25_000_000 : 0)
        })

        var heights: [CGFloat] = []
        for (buildLog, name) in [(nil, "detail-without-record"), (record, "detail-with-record")] as [(BuildLog?, String)] {
            let file = dir.appendingPathComponent("\(name).json")
            var state = CompanionState()
            state.language = .ko
            state.dex = [DexEntry(id: name, baseID: chain[0], finalID: chain[chain.count - 1], chainOrder: chain,
                                  rarity: .rare, caughtAt: day(20),
                                  names: Dictionary(uniqueKeysWithValues: chain.map { ($0, machine.names) }),
                                  buildLog: buildLog)]
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: MachineCatalog.allBundled, fileURL: file)
            let species = try XCTUnwrap(store.dexSpecies.first { $0.id == chain[chain.count - 1] })
            func mount(height: CGFloat) async throws -> NSView {
                let view = PokemonDetailView(store: store, species: species, onBack: {},
                                             providerNames: ["claude": "Claude Code", "codex": "Codex"],
                                             spriteStore: SpriteStore(directory: dir))
                    .frame(width: PopoverMetrics.contentWidth, height: height)
                    .background(Color.white).environment(\.colorScheme, .light)
                return try await mountOffscreen(view, width: PopoverMetrics.contentWidth, height: height)
            }
            let host = try await mount(height: 520)
            func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
            let scrollView = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
            let documentHeight = try XCTUnwrap(scrollView.documentView).frame.height
            heights.append(documentHeight)
            host.window?.close()
            if let output {
                let page = try await mount(height: documentHeight + 60)   // the whole page, nothing scrolled away
                try writePNG(page, to: output.appendingPathComponent("\(name).png"))
                page.window?.close()
            }
        }
        XCTAssertGreaterThanOrEqual(heights[1], heights[0] + 60)

        guard let output else { return }
        let raising = try build([.sd, .mgsd, .hg], [142_900_000, 285_700_000, 91_300_000], openedAt: t0, raising: true)
        let stopped = try build([.sd, .mgsd], [142_900_000, 167_300_000], openedAt: t0, caughtAt: day(6), stopped: true)
        let midBuild = try build([.sd, .mgsd, .hg, .rg], [248_600_000, 571_400_000], openedAt: nil, caughtAt: day(20),
                                 recordedFrom: 2, unattributed: 180_000_000)
        for (summary, name) in [(raising, "card-raising"), (stopped, "card-stopped"), (midBuild, "card-mid-build")] {
            let width = PopoverMetrics.scrollContentWidth
            let card = BuildRecordCard(summary: summary, l: L(.ko), locale: AppLanguage.ko.displayLocale,
                                       now: day(5), calendar: utc)
            let height = NSHostingController(rootView: card).sizeThatFits(in: CGSize(width: width, height: 10_000)).height
            let view = card.frame(width: width, height: height).background(Color.white).environment(\.colorScheme, .light)
            let host = try await mountOffscreen(view, width: width, height: height)
            try writePNG(host, to: output.appendingPathComponent("\(name).png"))
            host.window?.close()
        }
    }

    /// Mounts `view` in an off-screen light window, as `IndividualPickerRenderingTests` does.
    private func mountOffscreen<V: View>(_ view: V, width: CGFloat, height: CGFloat) async throws -> NSHostingView<V> {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func writePNG(_ view: NSView, to url: URL) throws {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
