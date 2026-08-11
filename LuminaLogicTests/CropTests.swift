import XCTest
@testable import Lumina

@MainActor
final class CropTests: XCTestCase {

    func testLayoutHashChangesOnEditAndReverts() {
        let recipe = EditRecipe(
            crop: EditCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.6),
            straightenDegrees: 0
        )
        var session = CropSession(photoID: UUID(), recipe: recipe)
        let baselineHash = session.working.layoutHash
        session.working.photoPanX = 0.3
        session.working.straightenDegrees = 2.4
        session.working.orientationFlipped = true
        XCTAssertNotEqual(session.working.layoutHash, baselineHash)
        session.revert()
        XCTAssertEqual(session.working.layoutHash, baselineHash)
    }

    func testCropHeaderNeverMentionsReject() {
        XCTAssertFalse(CropSessionCopy.header(straightenDegrees: 0).localizedCaseInsensitiveContains("reject"))
    }

    func testAspectLockAndFlipMutateWorkingState() {
        var session = CropSession(photoID: UUID(), recipe: .neutral)
        session.toggleAspectLock()
        XCTAssertTrue(session.working.aspectUnlocked)
        session.flipOrientation()
        XCTAssertTrue(session.working.orientationFlipped)
    }

    func testStraightenSoftMagnet() {
        var session = CropSession(photoID: UUID(), recipe: .neutral)
        session.setStraighten(0.2)
        XCTAssertEqual(session.working.straightenDegrees, 0, accuracy: 0.01)
        session.setStraighten(3.7)
        XCTAssertEqual(session.working.straightenDegrees, 3.7, accuracy: 0.01)
    }

    func testDraggingOutsideFlagClearsOnRevert() {
        let recipe = EditRecipe(crop: EditCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.6))
        var session = CropSession(photoID: UUID(), recipe: recipe)
        session.isDraggingOutside = true
        XCTAssertTrue(session.isDraggingOutside)
        session.revert()
        XCTAssertFalse(session.isDraggingOutside)
    }

    func testPanShiftsEffectiveCrop() {
        var state = CropLayoutState.from(recipe: EditRecipe(crop: EditCrop(x: 0.2, y: 0.2, width: 0.5, height: 0.5)))
        let baselineX = state.effectiveCrop.x
        state.photoPanX = 0.5
        XCTAssertLessThan(state.effectiveCrop.x, baselineX)
    }
}
