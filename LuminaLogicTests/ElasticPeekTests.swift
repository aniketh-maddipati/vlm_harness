import XCTest
@testable import Lumina

/// Checkpoint 04 — the one peek. Hold `⇥`: similar → set → flags; release returns;
/// a short tap pins; `Esc` closes. The prototype's `peekPatch` / `cyclePeek` /
/// `closedPeek` are the spec.
@MainActor
final class ElasticPeekTests: XCTestCase {

    // MARK: - Fixture

    private func asset(
        _ id: UUID,
        offset: TimeInterval,
        cull: CullDecision = .undecided,
        ext: String = "ARW",
        sensedIsPhone: Bool? = nil
    ) -> AssetRecord {
        AssetRecord(
            id: id,
            sourceKey: "k-\(id.uuidString)",
            source: SourceReference(
                originalPath: "/x/\(id.uuidString).\(ext)",
                relativePath: "\(id.uuidString).\(ext)",
                volumeID: "VOL",
                availability: .available
            ),
            filename: "asset-\(id.uuidString).\(ext)",
            cull: cull,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            sensedIsPhone: sensedIsPhone
        )
    }

    /// One moment: burst A (two frames), burst B (two frames, kept), a single, a phone
    /// frame; then a second moment an hour later with one kept frame.
    ///
    /// Order: a0 a1 b0 b1 s p | later
    private func seeded() -> (session: P0SessionModel, ids: [UUID]) {
        let ids = (0..<7).map { _ in UUID() }
        let session = P0SessionModel()
        session.assets = [
            asset(ids[0], offset: 0),
            asset(ids[1], offset: 0.5),
            asset(ids[2], offset: 10, cull: .keep),
            asset(ids[3], offset: 10.5, cull: .keep),
            asset(ids[4], offset: 40),
            asset(ids[5], offset: 50, ext: "HEIC", sensedIsPhone: true),
            asset(ids[6], offset: 3600, cull: .keep),
        ]
        session.route = .time
        session.focusedAssetID = ids[0]
        session.reconcileActiveChapter()
        XCTAssertEqual(session.chapters.count, 2, "the hour splits the shoot into two moments")
        return (session, ids)
    }

    // MARK: - Open · cycle · close

    func testHoldOpensSimilarThenCyclesSetAndFlagsAndWraps() {
        let (session, _) = seeded()
        XCTAssertNil(session.peek)

        session.openPeek(.related)
        XCTAssertEqual(session.peek, .related)
        XCTAssertFalse(session.peekPinned)
        XCTAssertTrue(session.tablePeekVisible)

        session.cyclePeek(by: 1)
        XCTAssertEqual(session.peek, .set)
        XCTAssertTrue(session.tablePeekVisible)

        session.cyclePeek(by: 1)
        XCTAssertEqual(session.peek, .flags)
        XCTAssertFalse(session.tablePeekVisible, "flags open the bursts; there is no bar")

        session.cyclePeek(by: 1)
        XCTAssertEqual(session.peek, .related, "↑↓ wrap")

        session.cyclePeek(by: -1)
        XCTAssertEqual(session.peek, .flags, "↑ wraps the other way")
    }

    func testOpeningTwiceDoesNotRestartTheHold() {
        let (session, _) = seeded()
        session.openPeek(.related, at: 100)
        session.cyclePeek(by: 1)
        session.openPeek(.related, at: 100.5)
        XCTAssertEqual(session.peek, .set, "a repeat ⇥ while held changes nothing")
        XCTAssertEqual(session.peekOpenedAt, 100)
    }

    func testPinnedTabClosesPastTheEndInsteadOfWrapping() {
        let (session, _) = seeded()
        session.openPeek(.related, at: 0)
        session.releasePeekKey(at: 0.1)
        XCTAssertTrue(session.peekPinned)

        session.cyclePeek(by: 1, wrap: false)
        XCTAssertEqual(session.peek, .set)
        session.cyclePeek(by: 1, wrap: false)
        XCTAssertEqual(session.peek, .flags)
        session.cyclePeek(by: 1, wrap: false)
        XCTAssertNil(session.peek, "⇥ past flags closes a pinned peek")
        XCTAssertFalse(session.peekPinned)
    }

    func testQuickReleasePinsAndSlowReleaseCloses() {
        let (session, _) = seeded()
        session.openPeek(.related, at: 10)
        session.releasePeekKey(at: 10 + P0SessionModel.peekPinTapSeconds - 0.01)
        XCTAssertEqual(session.peek, .related)
        XCTAssertTrue(session.peekPinned, "a tap pins")

        session.releasePeekKey(at: 20)
        XCTAssertEqual(session.peek, .related, "release means nothing once pinned")

        session.closePeek()
        session.openPeek(.related, at: 30)
        session.releasePeekKey(at: 30 + 2 * P0SessionModel.peekPinTapSeconds)
        XCTAssertNil(session.peek, "a hold returns on release")
    }

    func testSetIsSteppedOverWhenNothingIsKept() {
        let (session, ids) = seeded()
        for id in [ids[2], ids[3], ids[6]] {
            if let index = session.assets.firstIndex(where: { $0.id == id }) {
                session.assets[index].cull = .undecided
            }
        }
        XCTAssertTrue(session.finalSetAssetIDs.isEmpty)

        session.openPeek(.set)
        XCTAssertEqual(session.peek, .flags, "an empty set falls through to flags")

        session.cyclePeek(by: -1)
        XCTAssertEqual(session.peek, .related, "cycling backwards skips the empty set too")
        session.cyclePeek(by: 1)
        XCTAssertEqual(session.peek, .flags)
    }

    func testEscClosesThePeekBeforeLeavingFocus() {
        let (session, ids) = seeded()
        session.inspectingAssetID = ids[0]
        session.openPeek(.related, at: 0)
        session.releasePeekKey(at: 0.05)
        XCTAssertTrue(session.peekPinned)

        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertNil(session.peek)
        XCTAssertEqual(session.route, .focus, "the first Esc only closes the peek")

        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertEqual(session.route, .time)
    }

    func testEscLadderIgnoresAPeekTheOpenSurfaceCannotShow() {
        // The key owner guards Tab by route; if a peek ever leaks onto `.open`,
        // the ladder must still not swallow Esc there.
        let session = P0SessionModel()
        XCTAssertEqual(session.route, .open)
        XCTAssertNil(session.peek)
        XCTAssertFalse(P0EscLadder.handle(session: session))
    }

    // MARK: - The set peek walks the set

    func testSetPeekMovesTheCursorOntoTheNearestKeptFrameAndWalksTheSet() {
        let (session, ids) = seeded()
        session.setFocus(ids[4])
        session.openPeek(.set)
        XCTAssertEqual(session.peek, .set)
        XCTAssertTrue(session.walkingKeptRail)
        XCTAssertEqual(session.focusedAssetID, ids[3], "nearest kept frame in shoot order")

        session.moveFocus(dx: 1, dy: 0, columns: 6)
        XCTAssertEqual(session.focusedAssetID, ids[6], "→ walks the set, across the moment gap")
        session.moveFocus(dx: 1, dy: 0, columns: 6)
        XCTAssertEqual(session.focusedAssetID, ids[6], "the set has an end")
        session.moveFocus(dx: -1, dy: 0, columns: 6)
        session.moveFocus(dx: -1, dy: 0, columns: 6)
        XCTAssertEqual(session.focusedAssetID, ids[2])

        session.closePeek()
        XCTAssertFalse(session.walkingKeptRail)
        XCTAssertEqual(session.focusedAssetID, ids[2], "release keeps the cursor where the walk left it")
    }

    func testSetPeekWalksTheSetInsideFocusToo() {
        let (session, ids) = seeded()
        session.inspectingAssetID = ids[2]
        session.openPeek(.set)
        XCTAssertEqual(session.focusedAssetID, ids[2], "already in the set — the cursor stays")
        session.moveFocus(dx: 1, dy: 0, columns: 6)
        XCTAssertEqual(session.focusedAssetID, ids[3])
        XCTAssertEqual(session.route, .focus)
        XCTAssertEqual(session.stripAssetIDs, [ids[2], ids[3], ids[6]], "the strip shows the set")
        XCTAssertEqual(session.stripLabel, "set\nrelease ⇥")
        XCTAssertEqual(session.elasticHeadline, "2 of 3 in the set · release ⇥")
    }

    func testOpeningThePhotographKeepsAHeldSetWalk() {
        let (session, ids) = seeded()
        session.openPeek(.set)
        XCTAssertEqual(session.focusedAssetID, ids[2])
        session.openFocusedPhotograph()
        XCTAssertEqual(session.route, .focus)
        XCTAssertEqual(session.peek, .set)
        XCTAssertTrue(session.walkingKeptRail, "⏎ inside the set peek keeps walking the set")

        session.closeInspection()
        XCTAssertNil(session.peek, "leaving the photograph closes the peek")
        XCTAssertFalse(session.walkingKeptRail)
    }

    func testJumpingByNumber() {
        let (session, ids) = seeded()
        session.openPeek(.set)
        session.jumpInPeek(to: 3)
        XCTAssertEqual(session.focusedAssetID, ids[6])
        session.jumpInPeek(to: 9)
        XCTAssertEqual(session.focusedAssetID, ids[6], "past the end is nothing")
        XCTAssertEqual(session.peek, .set, "jumping keeps the peek open")

        session.closePeek()
        session.setFocus(ids[0])
        session.openPeek(.related)
        session.jumpInPeek(to: 2)
        XCTAssertEqual(session.focusedAssetID, ids[2], "2 is the second related frame")
        XCTAssertEqual(session.peek, .related)
    }

    func testPickingInSimilarGoesThereAndComesBack() {
        let (session, ids) = seeded()
        session.openPeek(.related)
        session.pickInPeek(ids[4])
        XCTAssertEqual(session.focusedAssetID, ids[4])
        XCTAssertNil(session.peek)

        session.openPeek(.set)
        session.pickInPeek(ids[6])
        XCTAssertEqual(session.focusedAssetID, ids[6])
        XCTAssertEqual(session.peek, .set, "the set peek only moves the cursor")
    }

    // MARK: - Similar

    func testRelatedOrdersBurstMatesThenTheMomentThenPhones() {
        let (session, ids) = seeded()
        let related = session.relatedFrames(to: ids[0])
        XCTAssertEqual(related.map(\.id), [ids[1], ids[2], ids[3], ids[4], ids[5]])
        XCTAssertEqual(related.map(\.relation), ["burst", "+10 s", "+11 s", "same moment", "phone"])
        XCTAssertEqual(related.map(\.key), ["1", "2", "3", "4", "5"])
        XCTAssertEqual(related.map(\.outlined), [false, true, true, false, false], "kept frames carry the set outline")
        XCTAssertFalse(related.contains { $0.id == ids[6] }, "another moment is not related")
    }

    func testRelatedPeekSeatsTheCursorAmongItsNeighbours() {
        let (session, ids) = seeded()
        let items = session.relatedPeekItems
        XCTAssertEqual(items.map(\.key), ["1", "2", "·", "3", "4", "5"])
        XCTAssertEqual(items[2].id, ids[0])
        XCTAssertTrue(items[2].isCursor)
        XCTAssertTrue(items[2].ringed)
        XCTAssertEqual(items[2].relation, "this one")
        XCTAssertEqual(items[2].facts, "")
        XCTAssertEqual(items.filter(\.ringed).count, 1, "only the cursor wears the ring")
    }

    func testAloneInTheMomentSaysSo() {
        let (session, ids) = seeded()
        session.setFocus(ids[6])
        let items = session.relatedPeekItems
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].facts, "nothing else in this moment")
    }

    func testSetPeekItemsNumberTheSetAndNameTheCursor() {
        let (session, ids) = seeded()
        session.openPeek(.set)
        let items = session.setPeekItems
        XCTAssertEqual(items.map(\.id), [ids[2], ids[3], ids[6]])
        XCTAssertEqual(items.map(\.key), ["1", "2", "3"])
        XCTAssertEqual(items.map(\.facts), ["cursor", "", ""])
        XCTAssertEqual(items.map(\.ringed), [true, false, false])
        XCTAssertEqual(session.peekTitle, "the set")
        XCTAssertTrue(session.peekSubtitle.hasPrefix("3 frames · ←→ walks"))
    }

    // MARK: - Layout

    func testPeekNumbersMatchTheDesign() {
        XCTAssertEqual(ElasticLayout.peekSetTile, 150)
        XCTAssertEqual(ElasticLayout.peekRelatedTile, 170)
        XCTAssertEqual(ElasticLayout.peekCursorTile, 220)
        XCTAssertEqual(ElasticLayout.peekPaddingTop, 12)
        XCTAssertEqual(ElasticLayout.tableGutter, 28)
        XCTAssertEqual(ElasticLayout.peekPaddingBottom, 16)
        XCTAssertEqual(ElasticLayout.peekFillOpacity, 0.94, accuracy: 1e-9)
        XCTAssertEqual(ElasticLayout.peekKeyBadgeHeight, 22)
        XCTAssertEqual(ElasticLayout.relatedKeyBadgeHeight, 24)
        XCTAssertEqual(ElasticLayout.relatedCursorGrow, 1.6, accuracy: 1e-9)
    }
}
