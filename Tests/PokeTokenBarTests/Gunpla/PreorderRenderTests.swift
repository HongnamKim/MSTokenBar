import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Writes PNGs of the pre-order and series box screens when `PTB_PREORDER_RENDER_DIR` names an existing folder;
/// skipped otherwise. Sample data only: sprites come from an empty directory, so no network is used.
@MainActor
final class PreorderRenderTests: XCTestCase {
    private typealias F = PreorderFixture
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        windows = []
    }

    private func writePNG<V: View>(_ view: V, height: CGFloat, to url: URL) async throws {
        let width = PopoverMetrics.contentWidth
        let host = NSHostingView(rootView: view.frame(width: width, height: height)
            .background(Color.white)
            .environment(\.colorScheme, .light))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        windows.append(window)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let bounds = host.bounds
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = bounds.size
        host.cacheDisplay(in: bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
        XCTAssertGreaterThan(png.count, 1000)
    }

    /// A store with an active build shows "건프라 박스" until its line loads; tick once and wait for it.
    private func loaded(_ store: CompanionStore) async throws -> CompanionStore {
        F.use(store, 0)
        let deadline = Date().addingTimeInterval(2)
        while store.currentLine == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(store.currentLine, "fixture: the active build's line must load before rendering")
        return store
    }

    func testWritePreorderScreens() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_PREORDER_RENDER_DIR"] else {
            throw XCTSkip("PTB_PREORDER_RENDER_DIR not set")
        }
        let output = URL(fileURLWithPath: directory)
        let spriteDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("preorder-sprites-\(UUID())")
        try FileManager.default.createDirectory(at: spriteDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: spriteDirectory) }
        let sprites = SpriteStore(directory: spriteDirectory)

        for (language, tag) in [(AppLanguage.ko, "ko"), (.en, "en")] {
            func state(_ build: (inout CompanionState) -> Void = { _ in }) -> CompanionState {
                var st = CompanionState()
                st.language = language
                build(&st)
                return st
            }
            let nav = PopoverNavigation()
            func shot<V: View>(_ name: String, height: CGFloat, _ view: V) async throws {
                try await writePNG(view, height: height, to: output.appendingPathComponent("\(name)-\(tag).png"))
            }

            let building = try await loaded(F.store(state { $0.active = F.building(F.zaku) }))
            try await shot("shop-cards", height: 330, VStack(spacing: 10) {
                SeriesBoxCard(store: building, onOpen: {})
                PreorderCard(store: building, nav: nav)
            }.padding(.horizontal, 10))

            let ordered = try await loaded(F.store(state {
                $0.active = F.building(F.zaku)
                $0.preorder = Preorder(machineID: F.unicornDestroy, boxesOpened: 1)
            }))
            try await shot("shop-preorder-active", height: 200, PreorderCard(store: ordered, nav: nav).padding(.horizontal, 10))

            try await shot("series-list", height: 420, SeriesBoxListView(store: building, onBack: {}, onBought: {})
                .padding(.horizontal, 10))
            let poor = try await loaded(F.store(state {
                $0.active = F.building(F.zaku)
                $0.usedSinceInstall = 3_000_000_000
            }))
            try await shot("series-list-unaffordable", height: 420, SeriesBoxListView(store: poor, onBack: {}, onBought: {})
                .padding(.horizontal, 10))
            try await shot("series-confirm-row", height: 60, ReplaceBoxConfirmRow(
                store: building, prompt: building.l.seriesBoxConfirm(building.displayName, building.seriesName("0080")),
                onCommit: {}, onCancel: {}).padding(.horizontal, 10))

            let hangar = try await loaded(F.store(state {
                $0.active = F.building(F.zaku)
                $0.dex = [F.finished(F.rx78), F.finished(F.gouf), F.finished(F.unicorn)]
            }))
            let pickNav = PopoverNavigation()
            pickNav.openPreorderPick()
            try await shot("pick-mode", height: 520, CollectionView(store: hangar, navigation: pickNav))

            try await shot("pick-modes-panel", height: 150, PreorderPickPanel(
                store: hangar, choice: .modes([F.unicorn, F.unicornDestroy, F.unicornAwakened]),
                onChooseMode: { _ in }, onConfirm: { _ in }, onCancel: {}).padding(.horizontal, 10))
            try await shot("pick-confirm-panel", height: 110, PreorderPickPanel(
                store: building, choice: .machine(F.gouf),
                onChooseMode: { _ in }, onConfirm: { _ in }, onCancel: {}).padding(.horizontal, 10))

            let box = try F.store(state { $0.preorder = Preorder(machineID: F.unicornDestroy, boxesOpened: 2) })
            try await shot("home-preorder-box", height: 200, CompanionHeader(store: box, spriteStore: sprites).padding(10))
            let home = try await loaded(F.store(state {
                $0.active = F.building(F.zaku)
                $0.preorder = Preorder(machineID: F.unicornDestroy, boxesOpened: 3)
            }))
            try await shot("home-preorder-building", height: 260, CompanionHeader(store: home, spriteStore: sprites).padding(10))
            let series = try F.store(state { $0.eggSeries = "0080"; $0.eggUsage = 500_000_000 })
            try await shot("home-series-badge", height: 200, CompanionHeader(store: series, spriteStore: sprites).padding(10))
        }
    }
}
