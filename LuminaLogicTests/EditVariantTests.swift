import XCTest
@testable import Lumina

@MainActor
final class EditVariantTests: XCTestCase {
    private let assetID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func makeAsset(recipe: EditRecipe) -> AssetRecord {
        AssetRecord(
            id: assetID,
            sourceKey: "one-raw",
            source: SourceReference(
                originalPath: "/proof/one-source.ARW",
                relativePath: "one-source.ARW",
                volumeID: "PROOF",
                availability: .available
            ),
            filename: "one-source.ARW",
            recipe: recipe
        )
    }

    func testExactElevenStepVariantProofChoosesAndUndoes() throws {
        let initial = EditRecipe(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            exposure: 0.1,
            temperature: 5_900,
            tint: 2,
            contrast: 7
        )
        let session = P0SessionModel()

        // 1. Begin with exactly one RAW asset and its canonical recipe.
        session.assets = [makeAsset(recipe: initial)]
        XCTAssertEqual(session.assets.map(\.id), [assetID])
        XCTAssertEqual(session.assets[0].recipe, initial)

        // 2. Branch four temporary variants from one shared base recipe.
        session.beginEditVariants(assetID: assetID)
        let started = try XCTUnwrap(session.workspaceState.editVariants)
        XCTAssertEqual(started.overrides.count, 4)

        // 3. Every branch refers to the same stable asset; no asset is copied.
        XCTAssertEqual(started.assetIDs, Array(repeating: assetID, count: 4))
        XCTAssertEqual(session.assets.count, 1)

        // 4. A shared exposure change reaches every unoverridden branch.
        session.setSharedVariantExposure(0.4)
        for index in 0..<4 {
            XCTAssertEqual(
                try XCTUnwrap(session.workspaceState.editVariants?.recipe(forVariantAt: index)).exposure,
                0.4,
                accuracy: 1e-9
            )
        }

        // 5. Give variant 1 a local white-balance layer.
        session.setVariantWhiteBalance(temperature: 7_200, tint: -8, at: 1)

        // 6. The white-balance layer changes only variant 1.
        XCTAssertEqual(session.workspaceState.editVariants?.recipe(forVariantAt: 0)?.temperature, 5_900)
        XCTAssertEqual(session.workspaceState.editVariants?.recipe(forVariantAt: 1)?.temperature, 7_200)
        XCTAssertEqual(session.workspaceState.editVariants?.recipe(forVariantAt: 1)?.tint, -8)
        XCTAssertEqual(session.workspaceState.editVariants?.recipe(forVariantAt: 2)?.temperature, 5_900)

        // 7. Give variant 2 a local exposure layer.
        session.setVariantExposure(-0.25, at: 2)
        XCTAssertEqual(session.workspaceState.editVariants?.recipe(forVariantAt: 2)?.exposure, -0.25)

        // 8. Change shared exposure again.
        session.setSharedVariantExposure(0.8)

        // 9. Shared exposure propagates except to variant 2; variant 1 keeps local WB.
        let branched = try XCTUnwrap(session.workspaceState.editVariants)
        XCTAssertEqual(branched.recipe(forVariantAt: 0)?.exposure, 0.8)
        XCTAssertEqual(branched.recipe(forVariantAt: 1)?.exposure, 0.8)
        XCTAssertEqual(branched.recipe(forVariantAt: 1)?.temperature, 7_200)
        XCTAssertEqual(branched.recipe(forVariantAt: 1)?.tint, -8)
        XCTAssertEqual(branched.recipe(forVariantAt: 2)?.exposure, -0.25)
        XCTAssertEqual(branched.recipe(forVariantAt: 3)?.exposure, 0.8)

        // 10. Choosing variant 1 collapses to one canonical recipe and one typed undo entry.
        session.focusEditVariant(at: 1)
        XCTAssertEqual(session.assets[0].recipe, initial, "focus must not commit")
        session.chooseFocusedEditVariant()
        let chosen = try XCTUnwrap(session.assets[0].recipe)
        XCTAssertNil(session.workspaceState.editVariants)
        XCTAssertEqual(chosen.exposure, 0.8)
        XCTAssertEqual(chosen.temperature, 7_200)
        XCTAssertEqual(chosen.tint, -8)
        XCTAssertEqual(chosen.contrast, initial.contrast)
        guard case .edit(let command)? = session.undoCoordinator.stack.last else {
            return XCTFail("Choice must use EditMutationCommand")
        }
        XCTAssertEqual(command.assetID, assetID)
        XCTAssertEqual(command.before, initial)
        XCTAssertEqual(command.after, chosen)

        // 11. One undo restores the exact initial canonical recipe.
        session.undoLast()
        XCTAssertEqual(session.assets[0].recipe, initial)
    }

    func testCancelRemovesVariantsWithoutPersistenceOrResourceOwnership() throws {
        let initial = EditRecipe(exposure: 0.2)
        let session = P0SessionModel()
        session.assets = [makeAsset(recipe: initial)]
        let assetsBefore = session.assets

        session.beginEditVariants(assetID: assetID)
        session.setSharedVariantExposure(1.0)
        session.setVariantWhiteBalance(temperature: 4_100, tint: 12, at: 3)

        session.cancelEditVariants()

        XCTAssertNil(session.workspaceState.editVariants)
        XCTAssertEqual(session.workspaceState.editVariantCancellationCount, 1)
        XCTAssertEqual(session.assets, assetsBefore)

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let canonical = try String(
            contentsOf: root.appendingPathComponent("Lumina/Models/P0State.swift"),
            encoding: .utf8
        )
        let workspace = try String(
            contentsOf: root.appendingPathComponent("Lumina/ViewModels/WorkspaceState.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(canonical.contains("EditVariant"))
        XCTAssertFalse(workspace.contains("PreparedRawSession"))
        XCTAssertFalse(workspace.contains(": Codable"))
    }

    func testVariantFocusTravelStagesWithoutCommitting() {
        let initial = EditRecipe(exposure: 0.15)
        let session = P0SessionModel()
        session.assets = [makeAsset(recipe: initial)]
        session.beginEditVariants(assetID: assetID)

        XCTAssertEqual(session.workspaceState.focusedEditVariantIndex, 0)
        session.moveEditVariantFocus(by: 1)
        session.moveEditVariantFocus(by: 1)
        XCTAssertEqual(session.workspaceState.focusedEditVariantIndex, 2)
        session.nudgeSharedVariantExposure(up: true)
        session.nudgeFocusedVariantExposure(up: false)
        session.nudgeFocusedVariantTemperature(up: true)
        session.nudgeFocusedVariantTint(up: false)
        XCTAssertEqual(session.assets[0].recipe, initial)
        XCTAssertFalse(session.canUndo)

        session.moveEditVariantFocus(by: 99)
        XCTAssertEqual(session.workspaceState.focusedEditVariantIndex, 3)
        session.moveEditVariantFocus(by: -99)
        XCTAssertEqual(session.workspaceState.focusedEditVariantIndex, 0)
        XCTAssertEqual(session.assets[0].recipe, initial)
    }

    func testKeyRoutingAndMinimalTrayPreserveDecisionBoundary() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let routing = try String(
            contentsOf: root.appendingPathComponent("Lumina/Views/P0/P0KeyRoutingModifier.swift"),
            encoding: .utf8
        )
        let editor = try String(
            contentsOf: root.appendingPathComponent("Lumina/Views/P0/P0SinglePhotoEditor.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(routing.contains("unmodified && lower == \"v\""))
        XCTAssertTrue(routing.contains("session.beginEditVariants()"))
        XCTAssertTrue(routing.contains("session.chooseFocusedEditVariant()"))
        XCTAssertTrue(routing.contains("session.cancelEditVariants()"))
        XCTAssertTrue(routing.contains("session.moveEditVariantFocus(by: -1)"))
        XCTAssertTrue(routing.contains("session.moveEditVariantFocus(by: 1)"))
        XCTAssertTrue(editor.contains("Variants · ⏎ chooses · Esc cancels"))
        XCTAssertTrue(editor.contains("ForEach(0..<EditVariantSession.count"))
        XCTAssertTrue(editor.contains("Shared exposure"))
        XCTAssertTrue(editor.contains("nudgeFocusedVariantTemperature"))
        XCTAssertTrue(editor.contains("nudgeFocusedVariantTint"))
        XCTAssertFalse(editor.contains("PreparedRawSession"))
        XCTAssertFalse(editor.contains("DevelopRenderScheduler"))
    }
}
