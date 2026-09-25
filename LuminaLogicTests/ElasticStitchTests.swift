import XCTest
@testable import Lumina

/// Stitch sequences the kept set. It writes `FinalSetOrder` and reuses out / export.
@MainActor
final class ElasticStitchTests: XCTestCase {

    private func asset(_ id: UUID, offset: TimeInterval, cull: CullDecision = .keep) -> AssetRecord {
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

    private func session(_ assets: [AssetRecord], order: [UUID] = []) -> P0SessionModel {
        let session = P0SessionModel()
        session.assets = assets
        session.route = .time
        session.focusedAssetID = assets.first?.id
        session.shoot = ShootRecord(
            name: "lumina-p0-stitch",
            assets: assets,
            finalSetOrder: FinalSetOrder(assetIDs: order)
        )
        session.reconcileActiveChapter()
        return session
    }

    func testFirstMoveFreezesChronologicalKeepsThenShifts() {
        let ids = (0..<3).map { _ in UUID() }
        let model = session(ids.enumerated().map { asset($1, offset: Double($0) * 10) })
        XCTAssertTrue(model.shoot?.finalSetOrder.assetIDs.isEmpty ?? false)
        XCTAssertEqual(model.finalSetAssetIDs, ids)

        XCTAssertTrue(model.moveInSet(ids[1], by: -1))
        XCTAssertEqual(model.shoot?.finalSetOrder.assetIDs, [ids[1], ids[0], ids[2]])
        XCTAssertEqual(model.finalSetAssetIDs, [ids[1], ids[0], ids[2]])
        XCTAssertEqual(model.assets.map(\.cull), Array(repeating: .keep, count: 3))
        XCTAssertEqual(model.undoCoordinator.undoLabel, "Undo Earlier in the set")
    }

    func testLaterThenUndoRestoresOrderWithoutTouchingCull() {
        let ids = (0..<3).map { _ in UUID() }
        let model = session(
            ids.enumerated().map { asset($1, offset: Double($0) * 10) },
            order: ids
        )
        let recipes = model.assets.map(\.recipe)

        XCTAssertTrue(model.moveInSet(ids[0], by: 1))
        XCTAssertEqual(model.finalSetAssetIDs, [ids[1], ids[0], ids[2]])
        XCTAssertEqual(model.focusedAssetID, ids[0])

        model.undoLast()
        XCTAssertEqual(model.finalSetAssetIDs, ids)
        XCTAssertEqual(model.assets.map(\.cull), Array(repeating: .keep, count: 3))
        XCTAssertEqual(model.assets.map(\.recipe), recipes)
        XCTAssertEqual(model.focusedAssetID, ids[0])
    }

    func testEndsDoNotWrapAndTravelDoesNotDecide() {
        let ids = (0..<2).map { _ in UUID() }
        let model = session(ids.enumerated().map { asset($1, offset: Double($0) * 10) }, order: ids)
        model.openStitch()
        XCTAssertTrue(model.stitchOpen)
        XCTAssertEqual(model.page, .stitch)

        XCTAssertFalse(model.moveInSet(ids[0], by: -1))
        XCTAssertFalse(model.moveInSet(ids[1], by: 1))
        XCTAssertEqual(model.finalSetAssetIDs, ids)

        model.stepStitchFocus(1)
        XCTAssertEqual(model.focusedAssetID, ids[1])
        model.stepStitchFocus(1)
        XCTAssertEqual(model.focusedAssetID, ids[1])
        XCTAssertEqual(model.assets.map(\.cull), Array(repeating: .keep, count: 2))
        XCTAssertTrue(model.selectedAssetIDs.isEmpty)
    }

    func testOutDropsTheFrameAndSameMarkClears() {
        let ids = (0..<2).map { _ in UUID() }
        let model = session(ids.enumerated().map { asset($1, offset: Double($0) * 10) }, order: ids)
        model.openStitch()
        model.setFocus(ids[0])

        XCTAssertEqual(model.classifyOut([ids[0]]), 1)
        XCTAssertEqual(model.finalSetAssetIDs, [ids[1]])
        XCTAssertEqual(model.asset(ids[0])?.cull, .reject)
        XCTAssertEqual(model.undoCoordinator.undoLabel, "Undo Out")

        XCTAssertEqual(model.classifyOut([ids[0]]), 1)
        XCTAssertEqual(model.asset(ids[0])?.cull, .undecided)
        XCTAssertEqual(model.undoCoordinator.undoLabel, "Undo Clear out")

        model.undoLast()
        XCTAssertEqual(model.asset(ids[0])?.cull, .reject)
    }

    func testExportHonorsTheMovedOrder() throws {
        let ids = (0..<3).map { _ in UUID() }
        let assets = ids.enumerated().map { asset($1, offset: Double($0) * 10) }
        let model = session(assets, order: ids)
        XCTAssertTrue(model.moveInSet(ids[2], by: -1))
        let plan = try P0ExportPlan.make(
            shootID: model.shoot!.id,
            assets: model.assets,
            order: model.shoot!.finalSetOrder.assetIDs,
            settings: .init()
        )
        XCTAssertEqual(plan.items.map(\.assetID), [ids[0], ids[2], ids[1]])
    }

    func testOpeningStitchDoesNotDecide() {
        let ids = [UUID(), UUID()]
        let model = session([
            asset(ids[0], offset: 0, cull: .keep),
            asset(ids[1], offset: 10, cull: .undecided),
        ])
        model.route = .focus
        model.inspectingAssetID = ids[0]
        model.openStitch()
        XCTAssertTrue(model.stitchOpen)
        XCTAssertEqual(model.route, .time)
        XCTAssertEqual(model.focusedAssetID, ids[0])
        XCTAssertEqual(model.asset(ids[0])?.cull, .keep)
        XCTAssertEqual(model.asset(ids[1])?.cull, .undecided)
    }

    func testEscLeavesStitchForTheTable() {
        let id = UUID()
        let model = session([asset(id, offset: 0)])
        model.openStitch()
        XCTAssertTrue(P0EscLadder.handle(session: model))
        XCTAssertFalse(model.stitchOpen)
        XCTAssertEqual(model.page, .chron)
        XCTAssertEqual(model.focusedAssetID, id)
    }

    func testLeadAndTrailMarkTheWalk() {
        let ids = (0..<3).map { _ in UUID() }
        let model = session(ids.enumerated().map { asset($1, offset: Double($0) * 10) }, order: ids)
        XCTAssertEqual(model.stitchSequenceMark(for: ids[0]), .lead)
        XCTAssertNil(model.stitchSequenceMark(for: ids[1]))
        XCTAssertEqual(model.stitchSequenceMark(for: ids[2]), .trail)

        let one = UUID()
        let singleton = session([asset(one, offset: 0)])
        XCTAssertNil(singleton.stitchSequenceMark(for: one))
    }
}
