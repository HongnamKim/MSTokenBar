import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class GunplaGradeBadgeTests: XCTestCase {
    func testEveryGradeFitsInItsOwnFooterAtAllPetSizes() throws {
        for grade in GunplaGrade.allCases {
            let image = try XCTUnwrap(GunplaGradeBadge.images[grade], grade.label)
            XCTAssertEqual(image.size.height, 13)
            for size in [CGFloat(48), 96, 384] {
                let renderer = ImageRenderer(content: GunplaGradeBadge(grade: grade, spriteSize: size))
                renderer.scale = 2
                let rendered = try XCTUnwrap(renderer.cgImage, grade.label)
                for speech in [false, true] {
                    let base = FloatingPetController.panelSize(petSize: size, showingBubble: speech)
                    let pet = FloatingPetController.panelSize(petSize: size, showingBubble: speech, grade: grade)
                    XCTAssertEqual(pet.width, base.width)
                    XCTAssertLessThanOrEqual(CGFloat(rendered.width) / renderer.scale, size)
                    XCTAssertEqual(pet.height - base.height, ceil(CGFloat(rendered.height) / renderer.scale) + 2)
                }
            }
        }
    }
}
