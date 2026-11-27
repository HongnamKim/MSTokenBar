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
        func header(_ lang: AppLanguage, series: String) throws -> CGSize {
            var st = CompanionState()
            st.language = lang
            st.eggSeries = series
            let store = try PreorderFixture.store(st)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("preorder-sprites-\(UUID())")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let view = CompanionHeader(store: store, spriteStore: SpriteStore(directory: dir))
            return size(view, width: PopoverMetrics.scrollContentWidth)
        }
        for lang in AppLanguage.allCases {
            let byLength = MachineCatalog.shared.series.sorted {
                (lang.resolveName($0.names) ?? "").count < (lang.resolveName($1.names) ?? "").count
            }
            let short = try header(lang, series: byLength.first!.id)
            let long = try header(lang, series: byLength.last!.id)
            XCTAssertLessThanOrEqual(long.width, PopoverMetrics.scrollContentWidth, "\(lang) \(byLength.last!.id)")
            XCTAssertLessThanOrEqual(long.height, short.height + 1, "\(lang) \(byLength.last!.id) wraps")
        }
    }
}
