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
