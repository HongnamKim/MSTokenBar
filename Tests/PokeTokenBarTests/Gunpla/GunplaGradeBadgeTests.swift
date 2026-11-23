import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class GunplaGradeBadgeTests: XCTestCase {
    func testCornerMarksAreHalfSizeAndRemainDistinct() throws {
        for size in [CGFloat(48), 88, 96, 136, 144, 384] {
            for displayScale in [CGFloat(1), 2] {
                var marks = Set<Data>()
                for grade in GunplaGrade.allCases {
                    XCTAssertNotNil(GunplaGradeBadge.images[grade], grade.label)
                    let original = ImageRenderer(content: GunplaGradeBadge(grade: grade, spriteSize: size))
                    original.scale = displayScale
                    let reference = try XCTUnwrap(original.cgImage, grade.label)
                    let badge = GunplaGradeBadge(grade: grade, spriteSize: size, isFloatingMark: true)
                    let renderer = ImageRenderer(content: badge)
                    // A half-size mark at twice the backing scale occupies the same number of pixels.
                    renderer.scale = displayScale * 2
                    let rendered = try XCTUnwrap(renderer.cgImage, grade.label)
                    XCTAssertEqual(rendered.width, reference.width, grade.label)
                    XCTAssertEqual(rendered.height, reference.height, grade.label)
                    let png = try XCTUnwrap(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]))
                    XCTAssertTrue(marks.insert(png).inserted, grade.label)
                }
            }
        }
    }
}
