import XCTest
@testable import Lumina

@MainActor
final class ElasticChronologyTests: XCTestCase {
    func testBoundariesFollowExistingChaptersAndDisplayedOrder() {
        let a = UUID(), b = UUID(), c = UUID()
        let first = ShootChapter(id: "first", startedAt: Date(timeIntervalSince1970: 100), assetIDs: [a, b], bursts: [])
        let second = ShootChapter(id: "second", startedAt: nil, assetIDs: [c], bursts: [])
        let marks = ElasticChronology.boundaries(orderedIDs: [b, a, c], chapters: [first, second], chronological: true)
        XCTAssertEqual(marks[b], first)
        XCTAssertNil(marks[a])
        XCTAssertEqual(marks[c], second)
        XCTAssertEqual(ElasticChronology.label(for: second), "Undated")
    }

    func testManualSetDoesNotClaimChronology() {
        let id = UUID()
        let chapter = ShootChapter(id: "chapter", startedAt: Date(), assetIDs: [id], bursts: [])
        XCTAssertTrue(ElasticChronology.boundaries(orderedIDs: [id], chapters: [chapter], chronological: false).isEmpty)
    }

    func testUnknownAssetsDoNotInventChapterOrTimestamp() {
        let id = UUID(), missing = UUID()
        let chapter = ShootChapter(id: "chapter", startedAt: nil, assetIDs: [id], bursts: [])
        let marks = ElasticChronology.boundaries(orderedIDs: [missing, id], chapters: [chapter], chronological: true)
        XCTAssertNil(marks[missing])
        XCTAssertEqual(marks[id]?.startedAt, nil)
        XCTAssertEqual(marks[id]?.id, chapter.id)
    }
    func testNavigationTracksLeadingChapterThroughGapsAndReverseScrolling() {
        let first = CGRect(x: 0, y: -180, width: 600, height: 250)
        let second = CGRect(x: 0, y: 70, width: 600, height: 200)
        XCTAssertEqual(ElasticChronology.activeChapter(frames: ["a": first, "b": second]), "a")
        XCTAssertEqual(ElasticChronology.activeChapter(frames: [
            "a": first.offsetBy(dx: 0, dy: -80), "b": second.offsetBy(dx: 0, dy: -80)
        ]), "b")
        XCTAssertEqual(ElasticChronology.activeChapter(frames: ["a": first, "b": second]), "a")
        XCTAssertEqual(ElasticChronology.activeChapter(frames: ["a": CGRect(x: 0, y: 20, width: 600, height: 200)]), "a")
        XCTAssertNil(ElasticChronology.activeChapter(frames: [:]))
    }

    func testChronologyMarkerDoesNotMoveFocusOrSelection() {
        let session = P0SessionModel()
        let id = UUID()
        session.focusedAssetID = id
        session.selectedAssetIDs = [id]
        session.chronologyViewportChapterID = "visible-chapter"
        XCTAssertEqual(session.focusedAssetID, id)
        XCTAssertEqual(session.selectedAssetIDs, [id])
        XCTAssertEqual(session.uiTestSnapshot().chronologyViewportChapterID, "visible-chapter")
    }
}
