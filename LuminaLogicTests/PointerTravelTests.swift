import XCTest
@testable import Lumina

/// Law 1 — pointer moves through media; explicit decision commands decide.
@MainActor
final class PointerTravelTests: XCTestCase {

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

    private func session(assetCount: Int) -> (P0SessionModel, [UUID]) {
        let ids = (0..<assetCount).map { _ in UUID() }
        let session = P0SessionModel()
        session.assets = ids.map { makeAsset(id: $0) }
        session.focusedAssetID = ids[0]
        return (session, ids)
    }

    func testFilmstripTapChangesFocusWithoutHiddenSelectionOrCull() {
        let (session, ids) = session(assetCount: 4)
        session.assets[0].cull = .keep
        session.inspectingAssetID = ids[0]
        let cullBefore = session.assets.map(\.cull)

        session.pointerTravel(to: ids[2])

        XCTAssertEqual(session.focusedAssetID, ids[2])
        XCTAssertEqual(session.inspectingAssetID, ids[2], "inspect filmstrip travel keeps the inspect latch")
        XCTAssertTrue(session.selectedAssetIDs.isEmpty, "no hidden persistent selection")
        XCTAssertEqual(session.selectionCount, 0)
        XCTAssertEqual(session.assets.map(\.cull), cullBefore)
        XCTAssertFalse(session.canUndo)
    }

    func testTableFrameTapFocusesWithoutDeciding() {
        let (session, ids) = session(assetCount: 3)

        session.pointerTravel(to: ids[1])

        XCTAssertEqual(session.focusedAssetID, ids[1])
        XCTAssertNil(session.inspectingAssetID)
        XCTAssertTrue(session.selectedAssetIDs.isEmpty)
        XCTAssertTrue(session.assets.allSatisfy { $0.cull == .undecided })
        XCTAssertFalse(session.canUndo)
        XCTAssertNil(session.assets[1].recipe)
    }

    func testPointerThenDecisionKeysApplyToCurrentFocus() {
        let (session, ids) = session(assetCount: 3)

        session.pointerTravel(to: ids[2])
        session.pressKeep()
        XCTAssertEqual(session.assets.first { $0.id == ids[2] }?.cull, .keep)
        XCTAssertEqual(session.assets.first { $0.id == ids[0] }?.cull, .undecided)

        session.pointerTravel(to: ids[1])
        session.pressReject()
        XCTAssertEqual(session.assets.first { $0.id == ids[1] }?.cull, .reject)
        XCTAssertEqual(session.assets.first { $0.id == ids[2] }?.cull, .keep)
        XCTAssertTrue(session.selectedAssetIDs.isEmpty)
    }

    func testInspectFromPointerFocusIsPreserved() {
        let (session, ids) = session(assetCount: 3)

        session.pointerTravel(to: ids[1])
        session.openFocusedPhotograph()
        XCTAssertEqual(session.inspectingAssetID, ids[1])
        XCTAssertEqual(session.focusedAssetID, ids[1])

        session.pointerTravel(to: ids[2])
        XCTAssertEqual(session.inspectingAssetID, ids[2])
        XCTAssertEqual(session.focusedAssetID, ids[2])
        XCTAssertTrue(session.selectedAssetIDs.isEmpty)
    }

    func testTwentyPointerTravelsDoNotGrowHiddenSelection() {
        let (session, ids) = session(assetCount: 20)
        XCTAssertEqual(session.selectionCount, 0)

        for id in ids {
            session.pointerTravel(to: id)
            XCTAssertEqual(session.focusedAssetID, id)
            XCTAssertTrue(session.selectedAssetIDs.isEmpty, "hidden selection must not grow")
            XCTAssertEqual(session.selectionCount, 0)
        }

        XCTAssertTrue(session.assets.allSatisfy { $0.cull == .undecided })
        XCTAssertFalse(session.canUndo)
    }

    func testPointerCallsitesAreTravelOnly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = [
            "Lumina/Views/P0/P0ChapterTableView.swift",
            "Lumina/Views/P0/ContactSheetCollection.swift",
            "Lumina/Views/P0/ElasticTableView.swift",
            "Lumina/Views/P0/ElasticFocusView.swift",
            "Lumina/ViewModels/P0SessionModel.swift",
        ]
        for rel in files {
            let text = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            XCTAssertFalse(text.contains("func selectClick"), "\(rel) must not own pointer-to-selection")
            XCTAssertFalse(text.contains("onSelectClick"), "\(rel) must not wire AppKit selection")
            XCTAssertFalse(text.contains("toggleSelectionOfFocused"), "\(rel) must not toggle hidden selection")
        }
        let table = try String(
            contentsOf: root.appendingPathComponent("Lumina/Views/P0/P0ChapterTableView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(table.contains("pointerTravel(to:"))
        XCTAssertFalse(table.contains("marks.selected"))
        let collection = try String(
            contentsOf: root.appendingPathComponent("Lumina/Views/P0/ContactSheetCollection.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(collection.contains("allowsMultipleSelection = true"))
        XCTAssertFalse(collection.contains("didSelectItemsAt"))
        XCTAssertTrue(collection.contains("onClickItem"))
    }
}
