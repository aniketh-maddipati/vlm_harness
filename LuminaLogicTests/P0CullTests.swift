import XCTest
@testable import Lumina

@MainActor
final class P0CullTests: XCTestCase {

    private func makeAsset(id: UUID, cull: CullDecision = .undecided, recipe: EditRecipe? = nil) -> AssetRecord {
        AssetRecord(
            id: id,
            sourceKey: "k-\(id.uuidString)",
            source: SourceReference(
                originalPath: "/x/\(id.uuidString).ARW",
                relativePath: "\(id.uuidString).ARW",
                volumeID: "VOL",
                availability: .available
            ),
            filename: "\(id.uuidString).ARW",
            cull: cull,
            recipe: recipe
        )
    }

    func testCullLeavesRecipeAndSelectionIndependent() {
        let a = UUID(), b = UUID()
        let session = P0SessionModel()
        session.assets = [
            makeAsset(id: a, recipe: EditRecipe(exposure: 0.3)),
            makeAsset(id: b),
        ]
        session.focusedAssetID = a
        session.selectedAssetIDs = [b]

        session.pressKeep()
        XCTAssertEqual(session.assets.first(where: { $0.id == a })?.cull, .keep)
        XCTAssertEqual(session.assets.first(where: { $0.id == a })?.recipe?.exposure, 0.3, accuracy: 1e-9)
        XCTAssertEqual(session.selectedAssetIDs, [b])
        XCTAssertEqual(session.focusedAssetID, a)
    }

    func testExportCountTracksKeptSet() {
        let a = UUID(), b = UUID(), c = UUID()
        let session = P0SessionModel()
        session.assets = [makeAsset(id: a), makeAsset(id: b), makeAsset(id: c)]
        session.focusedAssetID = b
        session.pressKeep()
        session.focusedAssetID = c
        session.pressKeep()
        XCTAssertEqual(session.exportCount, 2)
        session.focusedAssetID = c
        session.pressReject()
        XCTAssertEqual(session.exportCount, 1)
    }

    func testUndoRestoresPriorCullWithoutTouchingRecipe() {
        let a = UUID()
        let session = P0SessionModel()
        session.assets = [makeAsset(id: a, recipe: EditRecipe(exposure: 0.2))]
        session.focusedAssetID = a
        session.pressKeep()
        session.pressReject()
        let recipeBeforeUndo = session.assets[0].recipe
        session.undoLastCull()
        XCTAssertEqual(session.assets[0].cull, .keep)
        XCTAssertEqual(session.assets[0].recipe, recipeBeforeUndo)
    }

    func testFinalSetOrderChronologicalModeStaysEmpty() {
        var order = FinalSetOrder()
        let a = UUID(), b = UUID()
        order.reconcileKeptMembership(keptIDsInChronologicalOrder: [a, b])
        XCTAssertTrue(order.assetIDs.isEmpty)
    }

    func testFinalSetOrderCustomModeReconcilesMembership() {
        let a = UUID(), b = UUID(), c = UUID()
        var order = FinalSetOrder(assetIDs: [a, b])
        order.reconcileKeptMembership(keptIDsInChronologicalOrder: [b, c])
        XCTAssertEqual(order.assetIDs, [b, c])
    }

    func testGridPhotoNavigationPreservesFocusAndScroll() {
        let a = UUID(), b = UUID(), c = UUID()
        let session = P0SessionModel()
        session.assets = [makeAsset(id: a), makeAsset(id: b), makeAsset(id: c)]
        session.focusedAssetID = b
        session.scrollAnchor = 0.37
        session.selectedAssetIDs = [a, c]
        session.openFocusedPhotograph()
        XCTAssertEqual(session.inspectingAssetID, b)
        XCTAssertEqual(session.selectedAssetIDs, [a, c])
        session.closeInspection()
        XCTAssertNil(session.inspectingAssetID)
        XCTAssertEqual(session.focusedAssetID, b)
        XCTAssertEqual(session.scrollAnchor, 0.37, accuracy: 0.0001)
        XCTAssertTrue(session.pendingScrollRestore)
        XCTAssertEqual(session.selectedAssetIDs, [a, c])
    }
}
