import AppKit
import XCTest
@testable import PokeTokenBar

@MainActor
final class DisplayPetControllerTests: XCTestCase {
    func testShowsOnlyWithFloatingPetOnAChosenSuitAndAnAwakeDisplay() {
        let chosen = CompanionStore.RepresentativeSubject(speciesID: 100_012, isShiny: false)
        XCTAssertTrue(DisplayPetController.shouldShow(floatingPetEnabled: true, subject: chosen, displayAwake: true))
        XCTAssertFalse(DisplayPetController.shouldShow(floatingPetEnabled: false, subject: chosen, displayAwake: true),
                       "it follows the floating pet switch")
        XCTAssertFalse(DisplayPetController.shouldShow(floatingPetEnabled: true, subject: nil, displayAwake: true),
                       "switched off or nothing chosen")
        XCTAssertFalse(DisplayPetController.shouldShow(floatingPetEnabled: true, subject: chosen, displayAwake: false),
                       "a sleeping display drops the GIF loop")
    }

    /// Default spot is left of the main pet's default corner, so the two never start stacked.
    func testDefaultOriginSitsLeftOfTheMainPet() {
        let visible = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let origin = DisplayPetController.defaultOrigin(petSize: 96, visible: visible)
        XCTAssertEqual(origin, NSPoint(x: 1440 - 96 * 2 - 40, y: 25 + 24))
        XCTAssertLessThan(origin.x + 96, visible.maxX - 96 - 24, "no overlap with the main pet")
    }
}
