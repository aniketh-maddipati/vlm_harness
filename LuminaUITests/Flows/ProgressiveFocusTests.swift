import XCTest

/// Focus identity is synchronous; pixel quality may arrive later without
/// remounting or moving the single-photo surface.
final class ProgressiveFocusTests: LuminaUITestCase {
    func testNavigationKeepsOneStableFocusedSurface() {
        launch(LaunchConfig(fixture: .mixed60))
        let sheet = lumina.openShoot.open(.mixed60)
        let single = sheet.openFocused().assertVisible()
        let opened = lumina.requireProbe()
        guard let firstID = opened.focusedAssetID else {
            XCTFail("single-photo open has no focused identity")
            return
        }

        XCTAssertEqual(opened.inspectingAssetID, firstID)
        XCTAssertTrue(opened.chapterTableMounted, "inspect is a latch on the chapter table")
        XCTAssertEqual(opened.inspectPeripheryDimOpacity, 0.45, accuracy: 0.001)
        XCTAssertTrue(single.image.waitForExistence(timeout: UITestWait.elementExistence))
        let initialFrame = single.image.frame
        XCTAssertGreaterThan(opened.inspectionSettledLongEdge ?? 0, 0)

        single.navigateNext()
        let next = lumina.waitForProbe(timeout: UITestWait.transition) {
            $0.route == "singlePhoto"
                && $0.focusedAssetID != nil
                && $0.focusedAssetID != firstID
                && $0.inspectingAssetID == $0.focusedAssetID
        }

        XCTAssertNotEqual(next.focusedAssetID, firstID)
        XCTAssertEqual(next.inspectingAssetID, next.focusedAssetID)
        XCTAssertTrue(single.image.exists, "the permanent Metal leaf must not disappear")
        XCTAssertEqual(single.image.frame.origin.x, initialFrame.origin.x, accuracy: 1)
        XCTAssertEqual(single.image.frame.origin.y, initialFrame.origin.y, accuracy: 1)
        XCTAssertEqual(single.image.frame.width, initialFrame.width, accuracy: 1)
        XCTAssertEqual(single.image.frame.height, initialFrame.height, accuracy: 1)
        if let oriented = next.focusedOrientedIsPortrait,
           let presented = next.focusedPresentedIsPortrait {
            XCTAssertEqual(
                oriented,
                presented,
                "click-through must not present a RAW frame in the opposite aspect"
            )
        }
        Invariants.assert(next, app: app)
    }
}
