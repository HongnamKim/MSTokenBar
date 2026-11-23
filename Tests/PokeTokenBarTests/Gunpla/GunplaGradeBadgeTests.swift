import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class GunplaGradeBadgeTests: XCTestCase {
    func testSmallCornerMarksStayDistinctAtBothDisplayScales() throws {
        let sizes: [(CGFloat, Int)] = [(48, 4), (96, 6), (384, 12)]
        for (size, heightLimit) in sizes {
            for displayScale in [CGFloat(1), 2] {
                var marks = Set<Data>()
                for grade in GunplaGrade.allCases {
                    XCTAssertNotNil(GunplaGradeBadge.images[grade], grade.label)
                    let badge = GunplaGradeBadge(grade: grade, spriteSize: size, isFloatingMark: true)
                    let renderer = ImageRenderer(content: badge)
                    renderer.scale = displayScale
                    let rendered = try XCTUnwrap(renderer.cgImage, grade.label)
                    XCTAssertLessThanOrEqual(rendered.width, Int(ceil(size * displayScale / 6)), grade.label)
                    XCTAssertLessThanOrEqual(rendered.height, heightLimit * Int(displayScale), grade.label)
                    let png = try XCTUnwrap(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]))
                    XCTAssertTrue(marks.insert(png).inserted, grade.label)
                }
            }
        }
    }
}
