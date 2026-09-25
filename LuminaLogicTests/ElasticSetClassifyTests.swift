import CoreGraphics
import XCTest
@testable import Lumina

/// "in set?" puts frames in, and a second press takes them out as one command.
/// A drag rectangle selects; dropping that selection on the shelf still joins the set.
@MainActor
final class ElasticSetClassifyTests: XCTestCase {

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

    func testAPressPutsTheFrameInAndTheNextPressTakesItOut() {
        let id = UUID()
        let session = session([asset(id, offset: 0)])
        XCTAssertFalse(session.setToggleIsOn([id]))

        XCTAssertEqual(session.classifySet([id]), 1)
        XCTAssertTrue(session.isInFinalSet(id))
        XCTAssertTrue(session.setToggleIsOn([id]))
        XCTAssertEqual(session.undoCoordinator.undoLabel, "Undo In set")

        XCTAssertEqual(session.classifySet([id]), 1)
        XCTAssertFalse(session.isInFinalSet(id))
        XCTAssertEqual(session.asset(id)?.cull, .undecided)
        XCTAssertEqual(session.undoCoordinator.undoLabel, "Undo Out of the set")

        session.undoLast()
        XCTAssertTrue(session.isInFinalSet(id))
    }

    func testTheWholeShootComesInTogetherAndLeavesTogether() {
        let ids = (0..<3).map { _ in UUID() }
        let session = session([
            asset(ids[0], offset: 0, cull: .keep),
            asset(ids[1], offset: 10, cull: .reject),
            asset(ids[2], offset: 20),
        ])
        XCTAssertFalse(session.setToggleIsOn(ids), "one kept frame is not the whole shoot")

        XCTAssertEqual(session.classifySet(ids), 2)
        XCTAssertTrue(session.setToggleIsOn(ids))
        XCTAssertEqual(session.finalSetAssetIDs, ids)

        XCTAssertEqual(session.classifySet(ids), 3)
        XCTAssertTrue(session.finalSetAssetIDs.isEmpty)
        XCTAssertEqual(session.undoCoordinator.undoLabel, "Undo Out of the set")

        session.undoLast()
        XCTAssertEqual(session.finalSetAssetIDs, ids, "one undo restores the whole shoot")
    }

    func testASecondPressOnAPartialSetOnlyFillsIt() {
        let ids = [UUID(), UUID()]
        let session = session([
            asset(ids[0], offset: 0, cull: .keep),
            asset(ids[1], offset: 10),
        ])
        XCTAssertEqual(session.classifySet(ids), 1)
        XCTAssertEqual(session.asset(ids[0])?.cull, .keep)
        XCTAssertEqual(session.asset(ids[1])?.cull, .keep)
    }

    func testMarqueeHitsFramesInShootOrder() {
        let ids = [UUID(), UUID(), UUID()]
        let frames: [UUID: CGRect] = [
            ids[0]: CGRect(x: 0, y: 0, width: 10, height: 10),
            ids[1]: CGRect(x: 40, y: 0, width: 10, height: 10),
            ids[2]: CGRect(x: 20, y: 0, width: 10, height: 10),
        ]
        let hit = ElasticMarqueeSelection.ids(
            in: CGRect(x: 18, y: 0, width: 14, height: 10),
            frames: frames,
            order: ids
        )
        XCTAssertEqual(hit, [ids[2]], "the rect misses the first and the order stays the shoot's")

        let session = session(ids.enumerated().map { asset($1, offset: Double($0) * 10) })
        session.selectMarquee([ids[2], ids[0]])
        XCTAssertEqual(session.selectedAssetIDs, [ids[0], ids[2]])
        XCTAssertEqual(session.focusedAssetID, ids[0], "the marquee does not move the cursor")

        let added = session.dropOnShelf(session.selectedAssetIDs)
        XCTAssertEqual(added, 2)
        XCTAssertEqual(session.finalSetAssetIDs, [ids[0], ids[2]])
        XCTAssertTrue(session.selectedAssetIDs.isEmpty)
    }

    func testAPointIsNotAMarquee() {
        let id = UUID()
        XCTAssertEqual(
            ElasticMarqueeSelection.ids(in: CGRect(x: 1, y: 1, width: 0, height: 0), frames: [id: CGRect(x: 0, y: 0, width: 10, height: 10)], order: [id]),
            []
        )
    }
}
