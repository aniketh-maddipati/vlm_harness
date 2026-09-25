import XCTest
@testable import Lumina

@MainActor
final class ElasticPageTests: XCTestCase {

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

    func testFlipOrderAndEditCounts() {
        XCTAssertEqual(ElasticSurface.open.flipped(), .chron)
        XCTAssertEqual(ElasticSurface.chron.flipped(), .scroll)
        XCTAssertEqual(ElasticSurface.scroll.flipped(), .stitch)
        XCTAssertEqual(ElasticSurface.stitch.flipped(), .open)
        XCTAssertEqual(OpenShootArrangement.editProgress(edited: 4, total: 10).edited, 4)
        XCTAssertEqual(OpenShootArrangement.editProgress(edited: 4, total: 10).asShot, 6)
        XCTAssertEqual(OpenShootArrangement.editProgress(edited: 12, total: 10).asShot, 0)
    }

    func testFlipMovesBetweenPagesWithoutDeciding() {
        let ids = [UUID(), UUID()]
        let model = session(ids.enumerated().map { asset($1, offset: Double($0) * 30 * 60) })
        XCTAssertEqual(model.page, .chron)
        model.flipPage()
        XCTAssertEqual(model.page, .scroll)
        XCTAssertEqual(model.route, .focus)
        model.flipPage()
        XCTAssertEqual(model.page, .stitch)
        XCTAssertEqual(model.route, .time)
        XCTAssertTrue(model.stitchOpen)
        XCTAssertEqual(model.assets.map(\.cull), Array(repeating: .undecided, count: 2))
        model.flipPage()
        XCTAssertEqual(model.page, .open)
        XCTAssertEqual(model.route, .open)
    }

    func testNeighborStaysInsideTheRun() {
        XCTAssertEqual(ElasticPages.Index.neighbor(current: 0, count: 3, step: -1), nil)
        XCTAssertEqual(ElasticPages.Index.neighbor(current: 2, count: 3, step: 1), nil)
        XCTAssertEqual(ElasticPages.Index.neighbor(current: 1, count: 3, step: 1), 2)
        XCTAssertEqual(ElasticPages.Index.neighbor(current: 1, count: 3, step: -1), 0)
        XCTAssertEqual(ElasticPages.Index(position: 2, count: 4).label, "2 / 4")
        XCTAssertEqual(ElasticPages.Index(position: 0, count: 0).label, "")
    }

    func testMomentPageScrollsWithoutMovingTheCursor() {
        let ids = [UUID(), UUID(), UUID()]
        let model = session(ids.enumerated().map { asset($1, offset: Double($0) * 30 * 60) })
        XCTAssertGreaterThanOrEqual(model.chapters.count, 2)
        let focus = model.focusedAssetID
        let selection = model.selectedAssetIDs

        model.requestMomentPage(step: 1)
        XCTAssertEqual(model.momentPageRequest, model.chapters.dropFirst().first?.id)
        XCTAssertEqual(model.focusedAssetID, focus)
        XCTAssertEqual(model.selectedAssetIDs, selection)
        XCTAssertEqual(model.assets.map(\.cull), Array(repeating: .undecided, count: 3))

        model.momentPageRequest = nil
        model.chronologyViewportChapterID = model.chapters.last?.id
        model.requestMomentPage(step: 1)
        XCTAssertNil(model.momentPageRequest)
        XCTAssertEqual(model.focusedAssetID, focus)
    }

    func testFramePageTravelsAndDoesNotDecide() {
        let ids = [UUID(), UUID()]
        let model = session(ids.enumerated().map { asset($1, offset: Double($0) * 30 * 60) })
        model.route = .focus
        model.focusedAssetID = ids[0]
        XCTAssertEqual(model.framePage.label, "1 / 2")

        model.stepFramePage(1)
        XCTAssertEqual(model.focusedAssetID, ids[1])
        XCTAssertEqual(model.asset(ids[0])?.cull, .undecided)
        XCTAssertEqual(model.asset(ids[1])?.cull, .undecided)
        XCTAssertTrue(model.selectedAssetIDs.isEmpty)

        model.stepFramePage(1)
        XCTAssertEqual(model.focusedAssetID, ids[1])
    }
}
