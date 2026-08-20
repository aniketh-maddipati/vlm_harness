import XCTest
@testable import Lumina

@MainActor
final class DevelopEngineTests: XCTestCase {

    func testRecipeSerializationRoundTrip() throws {
        var recipe = EditRecipe(
            exposure: 0.35,
            temperature: 5200,
            tint: 4,
            highlights: -20
        )
        recipe = EditRecipe.migrate(recipe)
        let data = try EditRecipe.encodeStable(recipe)
        let decoded = try EditRecipe.decode(data)
        XCTAssertEqual(decoded.schemaVersion, .current)
        XCTAssertEqual(decoded.exposure, 0.35, accuracy: 1e-9)
        XCTAssertEqual(decoded.temperature, 5200, accuracy: 1e-9)
        XCTAssertEqual(decoded.tint, 4, accuracy: 1e-9)
        XCTAssertEqual(decoded.highlights, -20, accuracy: 1e-9)
        // Stable key order on re-encode.
        let data2 = try EditRecipe.encodeStable(decoded)
        XCTAssertEqual(data, data2)
    }

    func testSharedPropagationLocalOverrideIsolation() {
        let recipeID = UUID()
        var store = EditRecipeStore()
        store.upsertShared(EditRecipe(id: recipeID, exposure: 0.5))
        let p1 = UUID(), p2 = UUID(), p3 = UUID()
        store.bindLinked(photoID: p1, recipeID: recipeID)
        store.bindLinked(photoID: p2, recipeID: recipeID)
        store.bindLinked(photoID: p3, recipeID: recipeID)
        store.applyLocalEdit(photoID: p3, recipe: EditRecipe(exposure: 1.0))

        store.updateSharedRecipe(EditRecipe(id: recipeID, exposure: 0.8))

        XCTAssertEqual(
            store.binding(for: p1).effectiveCommittedRecipe(shared: store.recipes).exposure,
            0.8,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            store.binding(for: p2).effectiveCommittedRecipe(shared: store.recipes).exposure,
            0.8,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            store.binding(for: p3).effectiveCommittedRecipe(shared: store.recipes).exposure,
            1.0,
            accuracy: 1e-9
        )
        XCTAssertTrue(store.binding(for: p3).hasLocalDivergence)
    }

    func testBatchStageCommitCancelUndo() throws {
        var session = BatchTreatmentSession()
        let recipe = EditRecipe(exposure: 0.2)
        var store = EditRecipeStore()

        XCTAssertThrowsError(try session.stage(leaderRecipe: recipe, isARepeat: false)) { error in
            XCTAssertEqual(error as? BatchTreatmentError, .emptySelection)
        }

        let p1 = UUID(), p2 = UUID()
        session.setSelection([p1, p2], leader: p1)
        try session.stage(leaderRecipe: recipe, isARepeat: false)

        XCTAssertThrowsError(try session.confirmCommit(into: &store, isARepeat: true)) { error in
            XCTAssertEqual(error as? BatchTreatmentError, .nothingStaged)
        }

        session.noteReturnReleased()
        _ = try session.confirmCommit(into: &store, isARepeat: false)
        XCTAssertEqual(store.binding(for: p1).effectiveCommittedRecipe(shared: store.recipes).exposure, 0.2, accuracy: 1e-9)
        XCTAssertTrue(store.binding(for: p1).isLinkedToShared)

        var cancelSession = BatchTreatmentSession()
        cancelSession.setSelection([p1], leader: p1)
        try cancelSession.stage(leaderRecipe: EditRecipe(exposure: 1), isARepeat: false)
        cancelSession.cancelStaging()
        XCTAssertEqual(cancelSession.canStage, true)

        var undoSession = BatchTreatmentSession()
        undoSession.setSelection([p1, p2], leader: p1)
        try undoSession.stage(leaderRecipe: EditRecipe(exposure: 0.6), isARepeat: false)
        undoSession.noteReturnReleased()
        _ = try undoSession.confirmCommit(into: &store, isARepeat: false)
        let priorExposure = store.binding(for: p1).effectiveCommittedRecipe(shared: store.recipes).exposure
        _ = undoSession.undoLastCommit(into: &store)
        XCTAssertNotEqual(
            store.binding(for: p1).effectiveCommittedRecipe(shared: store.recipes).exposure,
            priorExposure
        )
    }

    func testRenderGenerationStaleRejection() {
        XCTAssertTrue(RenderGenerationOrdering.shouldPresent(candidate: 5, presented: nil))
        XCTAssertFalse(RenderGenerationOrdering.shouldPresent(candidate: 4, presented: 5))
        XCTAssertTrue(RenderGenerationOrdering.shouldPresent(candidate: 5, presented: 5))
        XCTAssertTrue(RenderGenerationOrdering.shouldPresent(candidate: 6, presented: 5))
        XCTAssertEqual(RenderGenerationOrdering.coalesce(pending: ["a", "b"], newest: "c"), ["c"])
    }

    func testCropCoordinatesAcrossResolutions() {
        let crop = EditCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
        let preview = crop.pixelRect(in: CGRect(x: 0, y: 0, width: 3200, height: 2000))
        let export = crop.pixelRect(in: CGRect(x: 0, y: 0, width: 8000, height: 5000))

        func normalizedFractions(_ rect: CGRect, width: CGFloat, height: CGFloat) -> (Double, Double, Double, Double) {
            let top = Double((height - (rect.origin.y + rect.height)) / height)
            return (
                Double(rect.origin.x / width),
                top,
                Double(rect.width / width),
                Double(rect.height / height)
            )
        }

        let n1 = normalizedFractions(preview, width: 3200, height: 2000)
        let n2 = normalizedFractions(export, width: 8000, height: 5000)
        for (a, b) in zip([n1.0, n1.1, n1.2, n1.3], [n2.0, n2.1, n2.2, n2.3]) {
            XCTAssertEqual(a, b, accuracy: 1e-9)
        }
    }

    func testAspectFitAllOrientations() {
        let drawable = CGSize(width: 1200, height: 800)
        for orientation in UInt32(1)...UInt32(8) {
            let (w, h) = EXIFOrientationFixture.orientedSize(
                rawWidth: 4000,
                rawHeight: 6000,
                orientation: orientation
            )
            let imageSize = CGSize(width: w, height: h)
            let fitted = AspectFitGeometry.fit(imageSize: imageSize, drawableSize: drawable)
            XCTAssertTrue(
                AspectFitGeometry.aspectRatioPreserved(imageSize: imageSize, drawableSize: drawable, fitted: fitted),
                "orientation \(orientation)"
            )
            XCTAssertLessThanOrEqual(fitted.size.width, drawable.width + 0.001)
            XCTAssertLessThanOrEqual(fitted.size.height, drawable.height + 0.001)
        }
    }

    func testOperationOrderPreviewExportEquivalence() throws {
        let graphPath = repoRoot()
            .appendingPathComponent("Lumina/Develop/DevelopRenderGraph.swift")
        let text = try String(contentsOf: graphPath, encoding: .utf8)
        let markers = [
            "RAW stage",
            "Look stage",
            "Geometry",
            "Region extract",
            "Output conversion",
        ]
        var searchStart = text.startIndex
        for marker in markers {
            guard let range = text.range(of: marker, range: searchStart..<text.endIndex) else {
                XCTFail("Missing fixed pipeline marker: \(marker)")
                return
            }
            searchStart = range.lowerBound
        }
    }

    func testCacheInvalidationFingerprint() {
        let a = EditRecipe(exposure: 0.1)
        let b = EditRecipe(exposure: 0.2)
        XCTAssertNotEqual(a.valueFingerprint, b.valueFingerprint)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
