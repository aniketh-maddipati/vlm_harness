import XCTest
@testable import Lumina

/// Checkpoint 04 — hold-`␣` is before. Everything as shot while held, release
/// returns, nothing mutates.
@MainActor
final class ElasticBeforeTests: XCTestCase {

    private func asset(_ id: UUID, offset: TimeInterval) -> AssetRecord {
        var record = AssetRecord(
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
        record.recipe = EditRecipe(exposure: 0.5)
        record.recipeSource = .hand
        return record
    }

    func testBeforeSpeaksInTheHeadlineAndTheStatusBarAndUnshiftsTheHistogram() {
        let a = UUID()
        let session = P0SessionModel()
        session.assets = [asset(a, offset: 0)]
        session.route = .time
        session.focusedAssetID = a
        session.reconcileActiveChapter()
        let frame = session.assets[0]

        XCTAssertNotEqual(session.histogramBinShift(for: frame), 0, "the edit moves the drawn bins")
        session.setShowingBefore(true)
        XCTAssertEqual(session.elasticHeadline, "before · everything as shot · release ␣")
        XCTAssertEqual(session.focusStateWord(for: frame), "before")
        XCTAssertEqual(session.histogramBinShift(for: frame), 0, "before shows the measurement as taken")
        XCTAssertEqual(session.assets[0].recipe?.exposure, 0.5, "before never touches the recipe")
        XCTAssertFalse(session.canUndo, "and never the undo stack")

        session.setShowingBefore(false)
        XCTAssertEqual(session.focusStateWord(for: frame), "yours")
    }

    func testBeforeSurvivesACursorMoveWhileHeld() {
        let a = UUID(), b = UUID()
        let session = P0SessionModel()
        session.assets = [asset(a, offset: 0), asset(b, offset: 5)]
        session.inspectingAssetID = a
        session.setShowingBefore(true)
        session.setFocus(b)
        XCTAssertEqual(session.focusedAssetID, b)
        XCTAssertTrue(session.showingBefore, "the key is still down; the neighbour is shown as shot too")
    }

    func testLeavingThePhotographReleasesBefore() {
        let a = UUID()
        let session = P0SessionModel()
        session.assets = [asset(a, offset: 0)]
        session.inspectingAssetID = a
        session.setShowingBefore(true)
        session.closeInspection()
        XCTAssertFalse(session.showingBefore)
    }

    func testBeforePressDurationIsTheDesignsTwoHundredMilliseconds() {
        XCTAssertEqual(ElasticLayout.beforePressSeconds, 0.2, accuracy: 1e-9)
    }
}
