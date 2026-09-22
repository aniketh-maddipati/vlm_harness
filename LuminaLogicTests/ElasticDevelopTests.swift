import XCTest
@testable import Lumina

/// Checkpoint 05 — the develop drawer: `E`, a nudge that ripples to the group, the
/// ratios, `R`, straighten, the profile, and `M`.
@MainActor
final class ElasticDevelopTests: XCTestCase {

    private func asset(_ id: UUID, offset: TimeInterval, cull: CullDecision = .undecided) -> AssetRecord {
        AssetRecord(
            id: id,
            sourceKey: "k-\(id.uuidString)",
            source: SourceReference(
                originalPath: "/x/\(id.uuidString).ARW",
                relativePath: "\(id.uuidString).ARW",
                volumeID: "VOL",
                availability: .available
            ),
            filename: "asset-\(id.uuidString).ARW",
            cull: cull,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000 + offset)
        )
    }

    /// Burst a0 a1 a2 (0.4 s apart), single s, then another moment m.
    private func seeded() -> (P0SessionModel, [UUID]) {
        let ids = (0..<5).map { _ in UUID() }
        let session = P0SessionModel()
        session.assets = [
            asset(ids[0], offset: 0), asset(ids[1], offset: 0.4), asset(ids[2], offset: 0.8),
            asset(ids[3], offset: 40, cull: .keep),
            asset(ids[4], offset: 3600),
        ]
        session.inspectingAssetID = ids[0]
        session.reconcileActiveChapter()
        return (session, ids)
    }

    func testEOpensTheDrawerOnlyInFocus() {
        let (session, _) = seeded()
        session.route = .time
        session.toggleDevelopDrawer()
        XCTAssertFalse(session.developDrawerOpen, "the table has no drawer")
        session.route = .focus
        session.toggleDevelopDrawer()
        XCTAssertTrue(session.developDrawerOpen)
        session.toggleDevelopDrawer()
        XCTAssertFalse(session.developDrawerOpen)
    }

    func testScopeIsSelectionThenBurstThenTheFrameAlone() {
        let (session, ids) = seeded()
        XCTAssertEqual(session.developScopeIDs(for: ids[0]), [ids[0], ids[1], ids[2]])
        XCTAssertEqual(session.developScopeIDs(for: ids[3]), [ids[3]])
        session.selectedAssetIDs = [ids[3], ids[4]]
        XCTAssertEqual(session.developScopeIDs(for: ids[0]), [ids[3], ids[4]])
        XCTAssertEqual(session.drawerScopeLine(for: ids[0]), "ripples to 2")
    }

    func testANudgeRipplesAsADeltaAndOneUndoBringsItAllBack() {
        let (session, ids) = seeded()
        // The burst mate already sits at +0.5; the delta lands on top of it.
        session.assets[1].recipe = EditRecipe(exposure: 0.5)
        session.assets[1].recipeSource = .auto

        session.beginEditGesture(for: ids[0])
        session.scrubEdit { $0.exposure = 1.0 }
        session.endDevelopGesture(\.exposure, range: -3...3)

        XCTAssertEqual(session.recipe(for: ids[0]).exposure, 1.0, accuracy: 1e-9)
        XCTAssertEqual(session.recipe(for: ids[1]).exposure, 1.5, accuracy: 1e-9, "the mate moves by the delta")
        XCTAssertEqual(session.recipe(for: ids[2]).exposure, 1.0, accuracy: 1e-9)
        XCTAssertEqual(session.recipe(for: ids[3]).exposure, 0, "outside the burst nothing moves")
        XCTAssertEqual(session.asset(ids[0])?.recipeSource, .hand)
        XCTAssertEqual(session.asset(ids[1])?.recipeSource, .autoHand, "an auto frame becomes auto + your hand")
        XCTAssertEqual(session.asset(ids[0])?.handRecipe?.exposure, 1.0, "the hand is cached for 3")
        XCTAssertEqual(session.undoCoordinator.undoLabel, "Undo Develop")

        session.undoLast()
        XCTAssertEqual(session.recipe(for: ids[0]).exposure, 0)
        XCTAssertEqual(session.recipe(for: ids[1]).exposure, 0.5, accuracy: 1e-9)
        XCTAssertEqual(session.asset(ids[1])?.recipeSource, .auto, "provenance comes back too")
        XCTAssertFalse(session.canUndo)
    }

    func testADeltaIsClampedToTheSliderOnTheMates() {
        let (session, ids) = seeded()
        session.assets[1].recipe = EditRecipe(exposure: 2.5)
        session.beginEditGesture(for: ids[0])
        session.scrubEdit { $0.exposure = 2.0 }
        session.endDevelopGesture(\.exposure, range: -3...3)
        XCTAssertEqual(session.recipe(for: ids[1]).exposure, 3.0, accuracy: 1e-9, "2.5 + 2 stops at the top")
    }

    func testRatiosRotateAndStraighten() {
        let (session, ids) = seeded()
        session.setCropRatio(.oneByOne)
        var recipe = session.recipe(for: ids[0])
        XCTAssertEqual(recipe.cropAspect, .oneByOne)
        XCTAssertEqual(session.cropSummary(for: recipe), "1:1")
        XCTAssertEqual(session.asset(ids[0])?.recipeSource, .hand)
        XCTAssertEqual(session.recipe(for: ids[1]).crop, nil, "geometry never ripples")

        session.rotateFocusedPhotograph()
        recipe = session.recipe(for: ids[0])
        XCTAssertEqual(recipe.straightenDegrees, 90)
        XCTAssertEqual(session.cropSummary(for: recipe), "1:1 · 90°")

        session.beginEditGesture(for: ids[0])
        session.scrubEdit { $0.straightenDegrees = 90 + 1.5 }
        session.endDevelopGesture(\.straightenDegrees, range: -370...370)
        recipe = session.recipe(for: ids[0])
        XCTAssertEqual(P0SessionModel.splitStraighten(recipe.straightenDegrees).fine, 1.5, accuracy: 1e-9)
        XCTAssertEqual(session.cropSummary(for: recipe), "1:1 · 90° · +1.5°")
        XCTAssertEqual(session.recipe(for: ids[1]).straightenDegrees, 1.5, accuracy: 1e-9, "a straighten nudge ripples like any slider")

        session.setCropRatio(.original)
        recipe = session.recipe(for: ids[0])
        XCTAssertNil(recipe.crop)
        XCTAssertEqual(recipe.cropAspect, .original)
        XCTAssertEqual(session.undoCoordinator.undoLabel, "Undo Crop")
    }

    func testCenteredCropHonoursTheFramesOwnAspect() {
        XCTAssertNil(ElasticCropRatio.threeByTwo.centeredCrop(imageAspect: 1.5), "the frame's own ratio is the full frame")
        XCTAssertNil(ElasticCropRatio.original.centeredCrop(imageAspect: 1.5))
        let square = ElasticCropRatio.oneByOne.centeredCrop(imageAspect: 1.5)
        XCTAssertEqual(square?.width ?? 0, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(square?.height ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(square?.x ?? 0, 1.0 / 6.0, accuracy: 1e-9)
        let wide = ElasticCropRatio.sixteenByNine.centeredCrop(imageAspect: 1.5)
        XCTAssertEqual(wide?.width ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(wide?.height ?? 0, 1.5 / (16.0 / 9.0), accuracy: 1e-9)
        let portraitOnPortrait = ElasticCropRatio.fourByFive.centeredCrop(imageAspect: 2.0 / 3.0)
        XCTAssertEqual(portraitOnPortrait?.width ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(portraitOnPortrait?.height ?? 0, (2.0 / 3.0) / 0.8, accuracy: 1e-9)
    }

    func testProfile() {
        let (session, ids) = seeded()
        session.setCameraProfile("Adobe Color")
        XCTAssertEqual(session.recipe(for: ids[0]).cameraProfile, "Adobe Color")
        XCTAssertEqual(session.asset(ids[0])?.recipeSource, .hand)
        XCTAssertEqual(P0SessionModel.cameraProfiles.count, 4)
        session.setCameraProfile("Adobe Color")
        XCTAssertEqual(session.undoCoordinator.undoLabel, "Undo Profile", "an unchanged pick pushes nothing new")
    }

    func testMatchCarriesOnlyTheCheckedGroupsToTheRightFrames() {
        let (session, ids) = seeded()
        session.assets[0].recipe = EditRecipe(exposure: 1, temperature: 5000, sharpness: 40, crop: .init(x: 0, y: 0.1, width: 1, height: 0.8), cameraProfile: "Adobe Color")
        session.assets[0].recipeSource = .hand
        XCTAssertEqual(session.matchGroups, [.light, .color, .profile])
        XCTAssertEqual(session.matchTargetIDs(for: ids[0]), [ids[1], ids[2], ids[3]], "the moment, without the cursor")
        XCTAssertEqual(session.matchScopeLine(for: ids[0]), "to the moment · 3")

        XCTAssertEqual(session.matchToCursor(), 3)
        let mate = session.recipe(for: ids[1])
        XCTAssertEqual(mate.exposure, 1)
        XCTAssertEqual(mate.temperature, 5000)
        XCTAssertEqual(mate.cameraProfile, "Adobe Color")
        XCTAssertEqual(mate.sharpness, 0, "detail was not checked")
        XCTAssertNil(mate.crop, "crop was not checked")
        XCTAssertEqual(session.asset(ids[1])?.recipeSource, .hand)
        XCTAssertEqual(session.recipe(for: ids[4]).exposure, 0, "another moment is untouched")
        XCTAssertEqual(session.undoCoordinator.undoLabel, "Undo Match")

        session.toggleMatchGroup(.crop)
        session.toggleMatchGroup(.light)
        XCTAssertEqual(session.matchGroups, [.color, .profile, .crop])
        session.selectedAssetIDs = [ids[4]]
        XCTAssertEqual(session.matchTargetIDs(for: ids[0]), [ids[4]])
        XCTAssertEqual(session.matchScopeLine(for: ids[0]), "to 1 selected · 1")
        XCTAssertEqual(session.matchToCursor(), 1)
        XCTAssertEqual(session.recipe(for: ids[4]).crop?.height ?? 0, 0.8, accuracy: 1e-9)
        XCTAssertEqual(session.recipe(for: ids[4]).exposure, 0, "light was unchecked this time")
    }

    func testMatchTargetsTheSetWhenTheCursorIsInIt() {
        let (session, ids) = seeded()
        session.assets[0].cull = .keep
        XCTAssertEqual(session.matchTargetIDs(for: ids[0]), [ids[3]])
        XCTAssertEqual(session.matchScopeLine(for: ids[0]), "to the set · 1")
    }

    func testCopyLinesAndControls() {
        let (session, ids) = seeded()
        let shot = session.assets[0]
        XCTAssertEqual(session.developSourceLine(for: shot), "as shot · nudge anything and it becomes yours · A for auto")
        session.assets[0].recipeSource = .sidecar
        XCTAssertTrue(session.developSourceLine(for: session.assets[0]).hasSuffix(".xmp · the sidecar is the truth · nudges ripple to the group as deltas"))
        _ = ids
        XCTAssertEqual(ElasticDevelopControl.exposed.map(\.name),
                       ["Exposure", "Contrast", "Highlights", "Shadows", "Temp", "Tint", "Vibrance", "Saturation", "Sharpness"],
                       "whites, blacks and dehaze are not shown")
        let exposure = ElasticDevelopControl.exposed[0]
        XCTAssertEqual(exposure.label(0.5), "+0.50")
        XCTAssertEqual(ElasticDevelopControl.exposed[4].label(6500), "6500K")
        XCTAssertEqual(ElasticDevelopControl.exposed[1].label(-12), "-12")
        XCTAssertEqual(ElasticLayout.drawerWidth, 256)
        XCTAssertEqual(ElasticLayout.straightenRange, 10)
        XCTAssertEqual(ElasticLayout.straightenStep, 0.1, accuracy: 1e-9)
    }
}
