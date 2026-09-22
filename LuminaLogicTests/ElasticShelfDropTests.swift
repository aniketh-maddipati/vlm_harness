import XCTest
@testable import Lumina

/// The set shelf as a drop target: what a drag carries, and what landing does.
@MainActor
final class ElasticShelfDropTests: XCTestCase {

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

    func testPayloadRoundTripsAndDropsJunk() {
        let ids = [UUID(), UUID(), UUID()]
        let payload = ElasticDragPayload.encode(ids)
        XCTAssertEqual(ElasticDragPayload.decode(payload), ids)
        XCTAssertEqual(ElasticDragPayload.decode(payload + ",not-a-uuid,," + ids[0].uuidString), ids, "junk and repeats fall out")
        XCTAssertEqual(ElasticDragPayload.decode(""), [])
    }

    func testADraggedFrameBringsTheSelectionOnlyWhenItIsInIt() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(ElasticDragPayload.ids(forDragging: a, selection: [a, b]), [a, b])
        XCTAssertEqual(ElasticDragPayload.ids(forDragging: c, selection: [a, b]), [c])
        XCTAssertEqual(ElasticDragPayload.ids(forDragging: c, selection: []), [c])
    }

    func testDropKeepsTheUndecidedLeavesMarksAloneAndSpendsTheSelection() {
        let ids = (0..<4).map { _ in UUID() }
        let session = P0SessionModel()
        session.assets = [
            asset(ids[0], offset: 0),
            asset(ids[1], offset: 10, cull: .keep),
            asset(ids[2], offset: 20, cull: .reject),
            asset(ids[3], offset: 30),
        ]
        session.route = .time
        session.focusedAssetID = ids[0]
        session.reconcileActiveChapter()
        session.selectedAssetIDs = [ids[0], ids[2], ids[3]]

        let added = session.dropOnShelf([ids[0], ids[2], ids[3], ids[1]])
        XCTAssertEqual(added, 2)
        XCTAssertEqual(session.finalSetAssetIDs, [ids[0], ids[1], ids[3]], "shoot order, the reject stays out")
        XCTAssertEqual(session.asset(ids[2])?.cull, .reject)
        XCTAssertTrue(session.selectedAssetIDs.isEmpty, "the drop spends the selection")
        XCTAssertEqual(session.undoCoordinator.undoLabel, "Undo Drop on the shelf")

        session.undoLast()
        XCTAssertEqual(session.finalSetAssetIDs, [ids[1]], "one ⌘Z puts every dropped frame back")
    }

    func testDroppingNothingNewIsANoOp() {
        let a = UUID()
        let session = P0SessionModel()
        session.assets = [asset(a, offset: 0, cull: .keep)]
        session.route = .time
        session.reconcileActiveChapter()
        XCTAssertEqual(session.dropOnShelf([a, UUID()]), 0, "kept already, unknown ignored")
        XCTAssertNil(session.undoCoordinator.undoLabel)
    }

    func testDropRingNumbersMatchTheDesign() {
        XCTAssertEqual(ElasticLayout.shelfDropRingWidth, 2)
        XCTAssertEqual(ElasticLayout.shelfDropRingInset, 2)
    }
}
