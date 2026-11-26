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

    func testTheDetailPageStartsOnTheRequestedBuild() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("build-nav-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(in: dir)
        let species = try XCTUnwrap(store.dexSpecies.first { $0.id == hg })

        func selectedTitle(initialInstanceID: String?) async throws -> String? {
            let page = initialInstanceID.map {
                PokemonDetailView(store: store, species: species, onBack: {}, initialInstanceID: $0,
                    spriteStore: SpriteStore(directory: dir))
            } ?? PokemonDetailView(store: store, species: species, onBack: {},
                spriteStore: SpriteStore(directory: dir))
            return try await selectedBuild(in: page)
        }

        let requested = try await selectedTitle(initialInstanceID: "fixture-0")
        let defaulted = try await selectedTitle(initialInstanceID: nil)
        XCTAssertEqual(requested?.hasPrefix("#2"), true, "requested: \(requested ?? "nil")")
        XCTAssertEqual(defaulted?.hasPrefix("#1"), true, "default: \(defaulted ?? "nil")")
    }

    func testTheCollectionViewHandsTheRequestedBuildToTheDetailPage() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("build-nav-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(in: dir)
        let page = try XCTUnwrap(store.dexLinkTargets[hg])

        func selectedTitle(_ open: (PopoverNavigation) -> Void) async throws -> String? {
            let nav = PopoverNavigation()
            nav.tab = .collection
            open(nav)
            return try await selectedBuild(in: CollectionView(store: store, navigation: nav))
        }

        let requested = try await selectedTitle { $0.openDexDetail(collectionID: page, instanceID: "fixture-0") }
        let defaulted = try await selectedTitle { $0.dexDetailCollectionID = page }
        XCTAssertEqual(requested?.hasPrefix("#2"), true, "requested: \(requested ?? "nil")")
        XCTAssertEqual(defaulted?.hasPrefix("#1"), true, "default: \(defaulted ?? "nil")")
    }

    /// Two builds of the same machine and grade: `fixture-0` is the older, `fixture-1` the newer.
    private func makeStore(in dir: URL) throws -> CompanionStore {
        let file = dir.appendingPathComponent("state.json")
        var state = CompanionState()
        state.language = .en
        state.dex = (0..<2).map { i in
            DexEntry(id: "fixture-\(i)", baseID: sd, finalID: hg, chainOrder: [sd, hg], rarity: .common,
                caughtAt: Date(timeIntervalSince1970: 1700000000 + Double(i)),
                names: [sd: ["en": "SD Gundam"], hg: ["en": "HG Gundam"]])
        }
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: MachineCatalog.allBundled, fileURL: file)
    }

    /// Mounts `view` off screen and reads the title of the detail page's build menu, its only pop-up button.
    private func selectedBuild<V: View>(in view: V) async throws -> String? {
        let host = NSHostingView(rootView: view.frame(width: PopoverMetrics.contentWidth, height: 520))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 520)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
        let menus = descendants(host).compactMap { $0 as? NSPopUpButton }
        XCTAssertEqual(menus.count, 1)
        return menus.first?.titleOfSelectedItem
    }
}
