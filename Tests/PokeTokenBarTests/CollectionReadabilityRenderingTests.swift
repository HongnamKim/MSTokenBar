import AppKit
import SwiftUI
import XCTest
import Vision
@testable import PokeTokenBar

/// Opt-in native captures use temporary saves and the bundled Gunpla art, never the user's collection.
/// The catalog fits one hangar page, so paging is covered by `DexBackNavigationTests` (20-machine catalog).
@MainActor
final class CollectionReadabilityRenderingTests: XCTestCase {
    func testGenerateCollectionReadabilityEvidence() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_COLLECTION_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_COLLECTION_SCREENSHOT_DIR for native collection layout evidence")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Real catalog machines (first 18 base kits), one HG cell each; names come from the catalog.
        let machines = Array(MachineCatalog.shared.machines.filter { !$0.isVariant && $0.grades.contains(.hg) }.prefix(18))
        let ids = machines.map { GunplaID.encode(machineID: $0.id, grade: .hg) }
        let names = Dictionary(uniqueKeysWithValues: zip(ids, machines).map { ($0, $1.names) })
        let requestedLanguage = ProcessInfo.processInfo.environment["PTB_COLLECTION_SCREENSHOT_LANGUAGE"]
        for language in AppLanguage.allCases where requestedLanguage == nil || language.rawValue == requestedLanguage {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("collection-readability-\(UUID()).json")
            defer { try? FileManager.default.removeItem(at: file) }
            var state = CompanionState()
            state.language = language
            state.dex = ids.enumerated().map { offset, id in
                DexEntry(baseID: id, finalID: id, chainOrder: [id], rarity: [.common, .uncommon, .rare, .legendary][offset % 4],
                         caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset)), names: names.filter { $0.key == id })
            }
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: MachineCatalog.shared, fileURL: file)
            for log in [false, true] {
                let navigation = PopoverNavigation()
                navigation.showingCollectionLog = log
                try await capture(CollectionView(store: store, navigation: navigation), language: language,
                                  expectedTexts: [.common, .uncommon, .rare, .legendary].map(store.l.rarityLabel),
                                  to: directory.appendingPathComponent("\(language.rawValue)-\(log ? "log" : "grid").png"))
            }
            let species = try XCTUnwrap(store.dexSpecies.first)
            try await capture(PokemonDetailView(store: store, species: species, onBack: {}), language: language,
                              expectedTexts: [species.name],
                              to: directory.appendingPathComponent("\(language.rawValue)-detail.png"))
        }
    }

    private func capture<V: View>(_ view: V, language: AppLanguage, expectedTexts: [String], to file: URL) async throws {
        let host = NSHostingView(rootView: view
            .frame(width: PopoverMetrics.contentWidth, height: 520)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, language.displayLocale))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 520)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.contentWidth, height: 520),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        XCTAssertEqual(host.bounds.width, 332, accuracy: 0.5)
        XCTAssertEqual(host.bounds.height, 520, accuracy: 0.5)
        let deadline = ContinuousClock.now + .seconds(5)
        var recognized = ""
        repeat {
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [language == .ko ? "ko-KR" : language == .ja ? "ja-JP" : language.rawValue]
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
            recognized = request.results?.filter { expectedTexts.count == 1 || $0.boundingBox.midY > 0.75 }
                .compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
            if expectedTexts.allSatisfy({ recognized.localizedCaseInsensitiveContains($0) }) {
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
                return
            }
        } while ContinuousClock.now < deadline
        XCTFail("Missing visible content \(expectedTexts) in \(file.lastPathComponent): \(recognized)")
    }
}
