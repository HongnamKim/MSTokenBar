import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class GunplaGradeBadgeTests: XCTestCase {
    func testCornerMarksAreHalfSizeAndRemainDistinct() throws {
        // Up to the in-app 3x cap (144-191pt) the floating mark is exactly half the in-app badge.
        for size in [CGFloat(48), 88, 96, 136, 144] {
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

    /// The floating pet goes up to 384pt; its corner mark must keep growing past the 144pt in-app cap.
    func testFloatingMarkGrowsWithThePet() throws {
        func height(_ size: CGFloat, floating: Bool) throws -> Int {
            let renderer = ImageRenderer(content: GunplaGradeBadge(grade: .hg, spriteSize: size, isFloatingMark: floating))
            renderer.scale = 4   // every step is a multiple of 0.25pt, so heights land on whole pixels
            return try XCTUnwrap(renderer.cgImage).height
        }
        let art = 13 * 4
        let expected: [(CGFloat, Double)] = [(48, 0.75), (95, 0.75), (96, 1), (143, 1), (144, 1.5),
                                             (192, 2), (288, 3), (384, 4)]
        for (size, scale) in expected {
            XCTAssertEqual(try height(size, floating: true), Int(Double(art) * scale), "pet \(size)pt")
            XCTAssertEqual(GunplaGradeBadge.imageScale(spriteSize: size, isFloatingMark: true), scale, "pet \(size)pt")
        }
        XCTAssertEqual(try height(384, floating: true), 2 * (try height(192, floating: true)))
        // In-app sprites keep their 3x cap.
        XCTAssertEqual(try height(384, floating: false), art * 3)
        XCTAssertEqual(GunplaGradeBadge.imageScale(spriteSize: 384, isFloatingMark: false), 3)
    }
}
