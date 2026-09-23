import XCTest
import CoreImage
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
        XCTAssertTrue(editor.contains("displayedVariantCIImage(at:"))
        XCTAssertTrue(editor.contains("DevelopMetalView"))
        XCTAssertTrue(editor.contains("Shared exposure"))
        XCTAssertTrue(editor.contains("nudgeFocusedVariantTemperature"))
        XCTAssertTrue(editor.contains("nudgeFocusedVariantTint"))
        XCTAssertFalse(editor.contains("PreparedRawSession"))
        XCTAssertFalse(editor.contains("DevelopRenderScheduler"))
        XCTAssertFalse(editor.contains("VariantImageService"))
        XCTAssertFalse(editor.contains("VariantRenderScheduler"))
    }

    func testFourVariantImagesBranchFromOnePinnedSource() {
        let source = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        DevelopRenderCounters.reset()
        let recipes = [
            EditRecipe(exposure: 0),
            EditRecipe(exposure: 0.4),
            EditRecipe(exposure: -0.25, temperature: 7_200),
            EditRecipe(exposure: 0.8, tint: -8),
        ]
        let branched = recipes.map {
            DevelopRenderGraph.branchInteractiveVariant(from: source, recipe: $0)
        }
        XCTAssertEqual(branched.count, 4)
        XCTAssertEqual(DevelopRenderCounters.snapshot().variantRenders, 4)
        XCTAssertEqual(DevelopRenderCounters.snapshot().preparedSessionCreated, 0)
        XCTAssertEqual(DevelopRenderCounters.snapshot().interactiveMaterializations, 0)
        XCTAssertEqual(DevelopRenderCounters.snapshot().gpuUploads, 0)
        XCTAssertEqual(DevelopRenderCounters.snapshot().graphRenders, 0)
        XCTAssertNotEqual(branched[0].extent, .zero)
    }

    func testHoldVUsesOnePreparedSessionAndRejectsStalePins() async throws {
        await PreparedRawSessionRegistry.shared.removeAll()
        DevelopRenderCounters.reset()
        let initial = EditRecipe(exposure: 0.1)
        let session = P0SessionModel()
        session.assets = [makeOnDiskAsset(recipe: initial)]

        session.beginEditVariants(assetID: assetID)
        session.beginEditVariants(assetID: assetID)
        session.beginEditVariants(assetID: assetID)
        try await Task.sleep(nanoseconds: 80_000_000)

        let afterBegin = DevelopRenderCounters.snapshot()
        XCTAssertEqual(afterBegin.preparedSessionCreated, 1)
        XCTAssertLessThan(afterBegin.interactiveMaterializations, 2)
        XCTAssertLessThan(afterBegin.gpuUploads, 2)

        let staleGeneration = session.variantPinnedGeneration
        let staleImage = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        session.cancelEditVariants()
        XCTAssertNil(session.workspaceState.editVariants)
        XCTAssertNil(session.variantPinnedSource)
        XCTAssertEqual(session.assets[0].recipe, initial)

        session.publishVariantPinnedSource(staleImage, generation: staleGeneration, assetID: assetID)
        XCTAssertNil(session.displayedVariantCIImage(at: 0), "stale pin must not publish after cancel")

        session.beginEditVariants(assetID: assetID)
        session.setVariantExposure(0.5, at: 0)
        session.setVariantWhiteBalance(temperature: 4_800, tint: 6, at: 1)
        let liveGeneration = session.variantPinnedGeneration
        XCTAssertNotEqual(liveGeneration, staleGeneration)
        let liveImage = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        // Each RAW intent needs its own baked source; a single as-shot pin can
        // no longer claim to represent four different white balances.
        var sources: [String: CIImage] = [:]
        for index in 0..<EditVariantSession.count {
            let recipe = try XCTUnwrap(session.workspaceState.editVariants?.recipe(forVariantAt: index))
            sources[recipe.rawIntent.fingerprint] = liveImage
        }
        session.publishVariantRawSources(sources, areRAW: true, generation: staleGeneration, assetID: assetID)
        XCTAssertNil(session.displayedVariantCIImage(at: 0))
        session.publishVariantRawSources(sources, areRAW: true, generation: liveGeneration, assetID: assetID)
        XCTAssertNotNil(session.displayedVariantCIImage(at: 0))
        XCTAssertNotNil(session.displayedVariantCIImage(at: 1))
        XCTAssertNotNil(session.displayedVariantCIImage(at: 2))
        XCTAssertNotNil(session.displayedVariantCIImage(at: 3))

        session.setFocus(UUID())
        XCTAssertNil(session.workspaceState.editVariants)
        XCTAssertNil(session.variantPinnedSource)
        XCTAssertNil(session.displayedVariantCIImage(at: 0))
        XCTAssertEqual(session.assets[0].recipe, initial)
        XCTAssertEqual(DevelopRenderCounters.snapshot().preparedSessionCreated, 1)
    }

    func testChooseAndRapidCancelKeepSingleRawPreparation() async throws {
        await PreparedRawSessionRegistry.shared.removeAll()
        DevelopRenderCounters.reset()
        let initial = EditRecipe(contrast: 7)
        let session = P0SessionModel()
        session.assets = [makeOnDiskAsset(recipe: initial)]

        for _ in 0..<4 {
            session.beginEditVariants(assetID: assetID)
            session.cancelEditVariants()
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(DevelopRenderCounters.snapshot().preparedSessionCreated, 0, "cancel before dispatch must not prepare a RAW")
        XCTAssertEqual(session.workspaceState.editVariantCancellationCount, 4)
        XCTAssertEqual(DevelopRenderCounters.snapshot().cancellations, 4)
        XCTAssertNil(session.variantPinnedSource)
        XCTAssertEqual(session.assets[0].recipe, initial)

        session.beginEditVariants(assetID: assetID)
        session.setSharedVariantExposure(0.3)
        session.focusEditVariant(at: 2)
        session.chooseFocusedEditVariant()
        XCTAssertNil(session.workspaceState.editVariants)
        XCTAssertNil(session.variantPinnedSource)
        let chosen = try XCTUnwrap(session.assets[0].recipe)
        XCTAssertEqual(chosen.exposure, 0.3, accuracy: 1e-9)
        XCTAssertEqual(chosen.contrast, 7)
        session.publishVariantPinnedSource(
            CIImage(color: .green).cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2)),
            generation: session.variantPinnedGeneration,
            assetID: assetID
        )
        XCTAssertNil(session.displayedVariantCIImage(at: 2), "choose must drop the pin")
        XCTAssertEqual(DevelopRenderCounters.snapshot().preparedSessionCreated, 0, "cancel before dispatch must not prepare a RAW")
    }

    func testVariantRenderPathStaysOnExistingOwners() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let session = try String(
            contentsOf: root.appendingPathComponent("Lumina/ViewModels/P0SessionModel.swift"),
            encoding: .utf8
        )
        let graph = try String(
            contentsOf: root.appendingPathComponent("Lumina/Develop/DevelopRenderGraph.swift"),
            encoding: .utf8
        )
        let prepared = try String(
            contentsOf: root.appendingPathComponent("Lumina/Develop/PreparedRawSession.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(session.contains("PreparedRawSessionRegistry.shared.session"))
        XCTAssertTrue(session.contains("interactivePinnedSource"))
        XCTAssertTrue(session.contains("branchInteractiveVariant"))
        XCTAssertTrue(session.contains("DevelopRenderQuality.interactive.defaultLongEdge"))
        XCTAssertTrue(graph.contains("func branchInteractiveVariant"))
        XCTAssertTrue(graph.contains("applyExposureAndWhiteBalance"))
        XCTAssertTrue(prepared.contains("func interactivePinnedSource"))
        XCTAssertTrue(prepared.contains("surface.texture != nil"))
        XCTAssertFalse(session.contains("VariantImageService"))
        XCTAssertFalse(session.contains("VariantRenderScheduler"))
        XCTAssertFalse(graph.contains("class Variant"))
    }

    private func makeOnDiskAsset(recipe: EditRecipe) -> AssetRecord {
        let raw = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/harness/fixtures/cp2/jpeg-sidecar-pair/DSC0001.ARW")
        return AssetRecord(
            id: assetID,
            sourceKey: "one-raw",
            source: SourceReference(
                originalPath: raw.path,
                relativePath: "DSC0001.ARW",
                volumeID: "PROOF",
                availability: .available
            ),
            filename: "DSC0001.ARW",
            recipe: recipe
        )
    }
}
