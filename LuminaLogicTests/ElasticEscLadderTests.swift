import XCTest
@testable import Lumina

/// The Esc ladder as the design orders it: peek → drawer → selection → route.
/// Each Esc unwinds exactly one step; the table itself has nowhere further to go.
@MainActor
final class ElasticEscLadderTests: XCTestCase {

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

    private func focused() -> (P0SessionModel, UUID, UUID) {
        let a = UUID(), b = UUID()
        let session = P0SessionModel()
        session.assets = [asset(a, offset: 0, cull: .keep), asset(b, offset: 5)]
        session.inspectingAssetID = a
        session.reconcileActiveChapter()
        return (session, a, b)
    }

    func testEveryStepInOrderOneEscEach() {
        let (session, a, b) = focused()
        session.developDrawerOpen = true
        session.selectedAssetIDs = [a, b]
        session.openPeek(.related, at: 0)
        session.releasePeekKey(at: 0.05)
        XCTAssertTrue(session.peekPinned)
        XCTAssertTrue(P0EscLadder.hasTransientDepth(session: session))

        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertNil(session.peek, "1 · peek")
        XCTAssertTrue(session.developDrawerOpen)
        XCTAssertEqual(session.selectedAssetIDs.count, 2)
        XCTAssertEqual(session.route, .focus)

        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertFalse(session.developDrawerOpen, "2 · drawer")
        XCTAssertEqual(session.selectedAssetIDs.count, 2)
        XCTAssertEqual(session.route, .focus)

        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertTrue(session.selectedAssetIDs.isEmpty, "3 · selection")
        XCTAssertEqual(session.route, .focus)

        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertEqual(session.route, .time, "4 · route")
        XCTAssertEqual(session.focusedAssetID, a, "the cursor stays where it was")

        XCTAssertFalse(P0EscLadder.handle(session: session), "the table is the end of the ladder")
        XCTAssertFalse(P0EscLadder.hasTransientDepth(session: session))
    }

    func testStitchUnwindsAfterTheFocusRoute() {
        let (session, a, _) = focused()
        session.openStitch()
        XCTAssertTrue(session.stitchOpen)
        XCTAssertEqual(session.route, .time)

        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertFalse(session.stitchOpen)
        XCTAssertEqual(session.focusedAssetID, a)
        XCTAssertFalse(P0EscLadder.handle(session: session), "the table is still the end")
    }

    func testTheSetPeekClosesWithoutMovingTheCursor() {
        let (session, a, _) = focused()
        session.openPeek(.set)
        XCTAssertTrue(session.walkingKeptRail)
        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertNil(session.peek)
        XCTAssertFalse(session.walkingKeptRail)
        XCTAssertEqual(session.focusedAssetID, a)
        XCTAssertEqual(session.route, .focus)
    }

    func testHoldsAndOpenBurstsDoNotAnswerToEsc() {
        let (session, _, _) = focused()
        session.route = .time
        session.setHoldingClipping(true)
        session.setShowingBefore(true)
        XCTAssertFalse(P0EscLadder.handle(session: session), "a held key releases with the key")
        XCTAssertTrue(session.holdingClipping)
        XCTAssertTrue(session.showingBefore)
    }

    func testTheOpenSurfaceIsNeverOnTheLadder() {
        let session = P0SessionModel()
        session.developDrawerOpen = true
        XCTAssertEqual(session.route, .open)
        XCTAssertTrue(P0EscLadder.handle(session: session), "a stray drawer flag still unwinds")
        XCTAssertFalse(P0EscLadder.handle(session: session))
    }
}
