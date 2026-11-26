import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Before/after renders for the "build stopped" wording. **Skipped unless `PTB_STOP_WORDING_RENDER_DIR`
/// names a directory:**
///
///     PTB_STOP_WORDING_RENDER_DIR=/some/dir swift test --filter StopWordingRenderTests
@MainActor
final class StopWordingRenderTests: XCTestCase {
    private let catalog = MachineCatalog.allBundled
    private var sd: Int { GunplaID.encode(machineID: 1, grade: .sd) }
    private var hg: Int { GunplaID.encode(machineID: 1, grade: .hg) }

    private func outputDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["PTB_STOP_WORDING_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("PTB_STOP_WORDING_RENDER_DIR not set — render only when asked")
        }
        return URL(fileURLWithPath: path)
    }

    private func store(_ state: CompanionState) throws -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stop-wording-\(UUID()).json")
        try JSONEncoder().encode(state).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: catalog, fileURL: url)
    }

    private func render<V: View>(_ view: V, to file: String, scrollToEnd: Bool = false) async throws {
        let directory = try outputDirectory()
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color.white).environment(\.colorScheme, .light))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        if scrollToEnd { scrollToBottom(host) }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(file))
    }

    private func scrollToBottom(_ view: NSView) {
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
            let y = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        view.subviews.forEach(scrollToBottom)
    }

    func test_buildLogList() async throws {
        _ = try outputDirectory()
        var state = CompanionState()
        state.language = .ko
        state.dex = [DexEntry(baseID: sd, finalID: hg, chainOrder: [sd, hg], rarity: .common,
                              caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                              releasedAt: Date(timeIntervalSince1970: 1_700_100_000))]
        let navigation = PopoverNavigation()
        navigation.showingCollectionLog = true
        try await render(CollectionView(store: try store(state), navigation: navigation), to: "build-log-list.png")
    }

    func test_shopBoxCard() async throws {
        _ = try outputDirectory()
        var state = CompanionState()
        state.language = .ko
        let path = [sd, hg]
        state.active = MonState(baseID: sd, pathIDs: [sd], plannedPathIDs: path, stageIndex: 0, usedAtStage: 0,
                                rarity: .rare, totalForms: path.count)
        try await render(ShopView(store: try store(state), nav: PopoverNavigation()), to: "shop-box-card.png", scrollToEnd: true)
    }
}
