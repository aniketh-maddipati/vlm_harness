import XCTest
@testable import Lumina

/// Chat-4 — note floater persistence and Esc order (floater before drawer).
@MainActor
final class ElasticNoteFloaterTests: XCTestCase {

    private func asset(_ id: UUID, offset: TimeInterval = 0) -> AssetRecord {
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
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000 + offset)
        )
    }

    private func focused() -> (P0SessionModel, UUID) {
        let id = UUID()
        let session = P0SessionModel()
        session.assets = [asset(id)]
        session.inspectingAssetID = id
        session.reconcileActiveChapter()
        return (session, id)
    }

    func testNoteRoundTripsThroughAssetRecordCodable() throws {
        let id = UUID()
        var record = asset(id)
        record.note = "keep the warm window light"
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(AssetRecord.self, from: data)
        XCTAssertEqual(decoded.note, "keep the warm window light")
    }

    func testMissingNoteDecodesAsNil() throws {
        let id = UUID()
        let record = asset(id)
        XCTAssertNil(record.note)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(AssetRecord.self, from: data)
        XCTAssertNil(decoded.note)
    }

    func testSetNoteWritesAssetAndClearsBlank() {
        let (session, id) = focused()
        session.setNote("  handshake  ", for: id)
        XCTAssertEqual(session.asset(id)?.note, "handshake")
        session.setNote("   ", for: id)
        XCTAssertNil(session.asset(id)?.note)
    }

    func testEscDismissesNoteFloaterBeforeDrawer() {
        let (session, _) = focused()
        session.developDrawerOpen = true
        session.noteFloaterOpen = true
        XCTAssertTrue(P0EscLadder.hasTransientDepth(session: session))

        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertFalse(session.noteFloaterOpen, "1 · note floater")
        XCTAssertTrue(session.developDrawerOpen, "drawer waits")

        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertFalse(session.developDrawerOpen, "2 · drawer")
        XCTAssertEqual(session.route, .focus)
    }

    func testDevelopGroupCycleWrapsToneColorDetailCrop() {
        let (session, _) = focused()
        session.developDrawerOpen = true
        session.expandedAdjustmentSection = .light
        session.cycleDevelopGroup(by: 1)
        XCTAssertEqual(session.expandedAdjustmentSection, .color)
        session.cycleDevelopGroup(by: 1)
        XCTAssertEqual(session.expandedAdjustmentSection, .detail)
        session.cycleDevelopGroup(by: 1)
        XCTAssertEqual(session.expandedAdjustmentSection, .crop)
        session.cycleDevelopGroup(by: 1)
        XCTAssertEqual(session.expandedAdjustmentSection, .light)
        session.cycleDevelopGroup(by: -1)
        XCTAssertEqual(session.expandedAdjustmentSection, .crop)
    }

    func testStickyDrawerStaysOpenAcrossFocusMoves() {
        let a = UUID(), b = UUID()
        let session = P0SessionModel()
        session.assets = [asset(a), asset(b, offset: 5)]
        session.inspectingAssetID = a
        session.reconcileActiveChapter()
        session.toggleDevelopDrawer()
        XCTAssertTrue(session.developDrawerOpen)
        session.setFocus(b)
        XCTAssertTrue(session.developDrawerOpen, "stays expanded while moving photographs")
        XCTAssertEqual(session.inspectingAssetID, b)
    }
}
