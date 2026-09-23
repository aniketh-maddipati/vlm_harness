import XCTest
@testable import Lumina

/// The README's ruling on the pointer: ⇧-click range · ⌘-click toggle · click moves
/// the cursor. Closes the item `docs/P0_CULLING.md` had open since before Elastic.
@MainActor
final class ElasticClickSelectionTests: XCTestCase {

    private func asset(_ id: UUID, offset: TimeInterval) -> AssetRecord {
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
            cull: .undecided,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000 + offset)
        )
    }

    /// Six frames over two moments: 0 1 2 | 3 4 5.
    private func seeded() -> (P0SessionModel, [UUID]) {
        let ids = (0..<6).map { _ in UUID() }
        let session = P0SessionModel()
        session.assets = ids.enumerated().map { index, id in
            asset(id, offset: Double(index) * 10 + (index >= 3 ? 3600 : 0))
        }
        session.route = .time
        session.focusedAssetID = ids[0]
        session.reconcileActiveChapter()
        return (session, ids)
    }

    func testPlainClickMovesTheCursorSetsTheAnchorAndClearsTheSelection() {
        let (session, ids) = seeded()
        session.selectedAssetIDs = [ids[4]]
        session.clickFrame(ids[2], shift: false, command: false)
        XCTAssertEqual(session.focusedAssetID, ids[2])
        XCTAssertEqual(session.selectionAnchorID, ids[2])
        XCTAssertTrue(session.selectedAssetIDs.isEmpty)
    }

    func testCommandClickTogglesWithoutMovingTheCursor() {
        let (session, ids) = seeded()
        session.clickFrame(ids[3], shift: false, command: true)
        XCTAssertEqual(session.selectedAssetIDs, [ids[3]])
        XCTAssertEqual(session.focusedAssetID, ids[0], "the cursor stays")
        XCTAssertEqual(session.selectionAnchorID, ids[0], "the anchor is the cursor when there was none")

        session.clickFrame(ids[5], shift: false, command: true)
        XCTAssertEqual(session.selectedAssetIDs, [ids[3], ids[5]])
        session.clickFrame(ids[3], shift: false, command: true)
        XCTAssertEqual(session.selectedAssetIDs, [ids[5]], "a second ⌘-click takes it out")
    }

    func testShiftClickSelectsTheRangeFromTheAnchorInShootOrder() {
        let (session, ids) = seeded()
        session.clickFrame(ids[1], shift: false, command: false)
        session.clickFrame(ids[4], shift: true, command: false)
        XCTAssertEqual(session.selectedAssetIDs, [ids[1], ids[2], ids[3], ids[4]], "across the moment gap")
        XCTAssertEqual(session.focusedAssetID, ids[4], "the cursor goes to the clicked frame")
        XCTAssertEqual(session.selectionAnchorID, ids[1], "the anchor holds")

        session.clickFrame(ids[0], shift: true, command: false)
        XCTAssertEqual(session.selectedAssetIDs, [ids[0], ids[1]], "backwards works and replaces the range")
    }

    func testShiftClickWithNoAnchorStartsAtTheCursor() {
        let (session, ids) = seeded()
        session.setFocus(ids[2])
        XCTAssertNil(session.selectionAnchorID)
        session.clickFrame(ids[3], shift: true, command: false)
        XCTAssertEqual(session.selectedAssetIDs, [ids[2], ids[3]])
    }

    func testEscClearsTheSelectionAndTheNextClickStartsClean() {
        let (session, ids) = seeded()
        session.clickFrame(ids[0], shift: false, command: false)
        session.clickFrame(ids[2], shift: true, command: false)
        XCTAssertEqual(session.selectedAssetIDs.count, 3)
        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertTrue(session.selectedAssetIDs.isEmpty)
        XCTAssertEqual(session.route, .time, "the table is still the table")
        XCTAssertEqual(session.elasticHeadline, session.elasticHeaderLine)
    }

    func testSelectionSpeaksInTheHeadline() {
        let (session, ids) = seeded()
        session.clickFrame(ids[1], shift: false, command: true)
        session.clickFrame(ids[2], shift: false, command: true)
        XCTAssertEqual(session.elasticHeadline, "2 selected · P to set · X out · Esc clears")
    }

    func testAnUnknownFrameIsIgnored() {
        let (session, ids) = seeded()
        session.clickFrame(UUID(), shift: true, command: false)
        XCTAssertTrue(session.selectedAssetIDs.isEmpty)
        XCTAssertEqual(session.focusedAssetID, ids[0])
    }
}
