import XCTest
@testable import Lumina

/// Plate selection is transient; pointer and keyboard culling remain explicit.
@MainActor
final class ElasticTablePointerTests: XCTestCase {

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

    private func session(_ assets: [AssetRecord]) -> P0SessionModel {
        let session = P0SessionModel()
        session.assets = assets
        session.route = .time
        session.focusedAssetID = assets.first?.id
        session.reconcileActiveChapter()
        return session
    }

    func testLeadAndTrailAreTheEndsOfTheFocusedBurst() {
        let ids = (0..<3).map { _ in UUID() }
        let session = session(ids.enumerated().map { asset($1, offset: Double($0) * 0.4) })
        XCTAssertEqual(session.chapters[0].bursts.count, 1)
        XCTAssertEqual(session.chapters[0].bursts[0].frameCount, 3)

        session.focusedAssetID = ids[1]
        XCTAssertEqual(session.sequenceMark(for: ids[0]), .lead)
        XCTAssertNil(session.sequenceMark(for: ids[1]))
        XCTAssertEqual(session.sequenceMark(for: ids[2]), .trail)
    }

    func testASingletonHasNoLeadOrTrail() {
        let id = UUID()
        let session = session([asset(id, offset: 0)])
        XCTAssertNil(session.sequenceMark(for: id))
    }

    func testLeadAndTrailClearWhenFocusLeavesTheBurst() {
        let burst = (0..<2).map { _ in UUID() }
        let other = UUID()
        let session = session([
            asset(burst[0], offset: 0),
            asset(burst[1], offset: 0.4),
            asset(other, offset: 10),
        ])
        session.focusedAssetID = burst[0]
        XCTAssertEqual(session.sequenceMark(for: burst[0]), .lead)
        XCTAssertEqual(session.sequenceMark(for: burst[1]), .trail)

        session.focusedAssetID = other
        XCTAssertNil(session.sequenceMark(for: burst[0]))
        XCTAssertNil(session.sequenceMark(for: burst[1]))
        XCTAssertNil(session.sequenceMark(for: other))
    }

    func testAClickOnAnotherPlateSelectsWithoutChangingCull() {
        let ids = [UUID(), UUID()]
        let session = session(ids.enumerated().map { asset($1, offset: Double($0) * 10) })
        session.focusedAssetID = ids[0]

        session.clickTablePlate(ids[1], shift: false, command: false)
        XCTAssertEqual(session.focusedAssetID, ids[1])
        XCTAssertEqual(session.selectedAssetIDs, [ids[1]])
        XCTAssertEqual(session.asset(ids[0])?.cull, .undecided)
        XCTAssertEqual(session.asset(ids[1])?.cull, .undecided)
    }

    func testRepeatedClicksToggleSelectionWithoutChangingKeptSetOrAdvancing() {
        let ids = [UUID(), UUID()]
        let session = session([
            asset(ids[0], offset: 0, cull: .keep),
            asset(ids[1], offset: 10),
        ])
        let keptBefore = session.finalSetAssetIDs

        session.clickTablePlate(ids[0], shift: false, command: false)
        XCTAssertEqual(session.selectedAssetIDs, [ids[0]])
        XCTAssertEqual(session.focusedAssetID, ids[0])
        XCTAssertEqual(session.finalSetAssetIDs, keptBefore)

        session.clickTablePlate(ids[0], shift: false, command: false)
        XCTAssertTrue(session.selectedAssetIDs.isEmpty)
        XCTAssertEqual(session.focusedAssetID, ids[0])
        XCTAssertEqual(session.finalSetAssetIDs, keptBefore)
        XCTAssertEqual(session.asset(ids[0])?.cull, .keep)
    }

    func testSelectionModifiersRemainNonDestructive() {
        let ids = (0..<3).map { _ in UUID() }
        let session = session(ids.enumerated().map { asset($1, offset: Double($0) * 10) })
        session.clickTablePlate(ids[0], shift: false, command: false)
        session.clickTablePlate(ids[2], shift: true, command: false)
        XCTAssertEqual(session.selectedAssetIDs, ids)
        session.clickTablePlate(ids[1], shift: false, command: true)
        XCTAssertEqual(session.selectedAssetIDs, [ids[0], ids[2]])
        XCTAssertTrue(session.finalSetAssetIDs.isEmpty)
    }

    func testUnknownPlateDoesNotChangeSelection() {
        let id = UUID()
        let session = session([asset(id, offset: 0)])
        session.clickTablePlate(id, shift: false, command: false)
        session.clickTablePlate(UUID(), shift: false, command: false)
        XCTAssertEqual(session.selectedAssetIDs, [id])
        XCTAssertEqual(session.focusedAssetID, id)
    }

    func testAPlateClickNeverRejects() {
        let ids = [UUID(), UUID()]
        let session = session(ids.enumerated().map { asset($1, offset: Double($0) * 10) })
        session.focusedAssetID = ids[0]

        session.clickTablePlate(ids[1], shift: false, command: false)
        session.clickTablePlate(ids[1], shift: false, command: false)
        XCTAssertNotEqual(session.asset(ids[0])?.cull, .reject)
        XCTAssertNotEqual(session.asset(ids[1])?.cull, .reject)
    }

    func testOffPhotoCommandProbeFollowsSelectionRatherThanFocus() {
        let id = UUID()
        let session = session([asset(id, offset: 0)])
        XCTAssertFalse(session.uiTestSnapshot().pointerCullTargetsVisible)
        XCTAssertFalse(session.uiTestSnapshot().elasticOutVisible)
        session.clickTablePlate(id, shift: false, command: false)
        XCTAssertTrue(session.uiTestSnapshot().pointerCullTargetsVisible)
        XCTAssertTrue(session.uiTestSnapshot().elasticOutVisible)
        session.clickTablePlate(id, shift: false, command: false)
        XCTAssertFalse(session.uiTestSnapshot().pointerCullTargetsVisible)
        XCTAssertFalse(session.uiTestSnapshot().elasticOutVisible)
    }

    func testKeyboardXStillRejectsAndClears() {
        let ids = [UUID(), UUID()]
        let session = session(ids.enumerated().map { asset($1, offset: Double($0) * 10) })
        session.focusedAssetID = ids[0]

        session.pressReject()
        XCTAssertEqual(session.asset(ids[0])?.cull, .reject)
        XCTAssertEqual(session.focusedAssetID, ids[1], "X advances like the key")

        session.focusedAssetID = ids[0]
        session.pressReject()
        XCTAssertEqual(session.asset(ids[0])?.cull, .undecided)
        XCTAssertEqual(session.focusedAssetID, ids[0], "same-mark-clears stays put")
    }
}
