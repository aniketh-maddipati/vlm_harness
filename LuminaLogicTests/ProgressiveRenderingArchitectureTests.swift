import XCTest
@testable import Lumina

/// Compile lock: `lookIntent` / `cacheKey` must be reachable off the main actor.
nonisolated func nonisolatedLookIntentFingerprint(_ recipe: EditRecipe) -> String {
    recipe.lookIntent.fingerprint
}

nonisolated func nonisolatedRenderCacheKey(_ request: RawRenderRequest) -> String {
    request.cacheKey
}

nonisolated func nonisolatedEnsureProxy(for photo: PhotoRecord, projectName: String) -> URL? {
    DevelopEngine.ensureProxy(for: photo, projectName: projectName)
}

nonisolated func nonisolatedPhotoTierPath(_ photo: PhotoRecord) -> String? {
    PhotoImageTier.proxy.path(for: photo)
}

final class ProgressiveRenderingArchitectureTests: XCTestCase {
    func testLegacyMachineTierCannotBecomeP0Decision() {
        let machineTier = PhotoRecord(
            rawPath: "/tmp/frame.arw",
            filename: "frame.arw",
            tier: .reject,
            userDecidedAt: nil
        )
        let migrated = ShootMigration.asset(from: machineTier, shootRoot: nil)
        XCTAssertEqual(migrated.cull, .undecided)
    }

    func testTimestampedHandTierCrossesP0DecisionBoundary() {
        let handTier = PhotoRecord(
            rawPath: "/tmp/frame.arw",
            filename: "frame.arw",
            tier: .keep,
            userDecidedAt: Date()
        )
        let migrated = ShootMigration.asset(from: handTier, shootRoot: nil)
        XCTAssertEqual(migrated.cull, .keep)
    }

    func testSceneAndSignalsAreIndependentOfCull() {
        let asset = AssetRecord(
            id: UUID(),
            sourceKey: "fixture",
            source: SourceReference(originalPath: "/tmp/frame.arw", relativePath: "frame.arw"),
            filename: "frame.arw",
            cull: .undecided,
            sharpness: 0.8,
            exposureHealth: 0.7,
            faceQuality: 0.6,
            faceDetected: true,
            burstID: "burst-1",
            clusterID: "scene-1"
        )
        XCTAssertEqual(asset.sceneMembership.sceneID, "scene-1")
        XCTAssertEqual(asset.qualitySignals.sharpness, 0.8)
        XCTAssertEqual(asset.cull, .undecided)
    }

    func testDisplayTargetParticipatesInRenderCacheKey() {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/frame.arw")
        let compact = RawRenderRequest(
            generation: 1,
            photoID: id,
            rawURL: url,
            recipe: .neutral,
            quality: .settled,
            longEdgeCap: 2560
        )
        let retina = RawRenderRequest(
            generation: 2,
            photoID: id,
            rawURL: url,
            recipe: .neutral,
            quality: .settled,
            longEdgeCap: 4096
        )
        XCTAssertNotEqual(compact.cacheKey, retina.cacheKey)
    }

    func testLookIntentIsReachableFromTheRenderDataPlane() {
        let base = EditRecipe()
        let look = base.updating { $0.contrast = 25 }
        let lookPrint = nonisolatedLookIntentFingerprint(look)
        XCTAssertNotEqual(nonisolatedLookIntentFingerprint(base), lookPrint)
        XCTAssertEqual(base.rawIntent.fingerprint, look.rawIntent.fingerprint)

        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let url = URL(fileURLWithPath: "/tmp/frame.arw")
        let baseKey = nonisolatedRenderCacheKey(
            RawRenderRequest(generation: 1, photoID: id, rawURL: url, recipe: base, quality: .interactive)
        )
        let lookKey = nonisolatedRenderCacheKey(
            RawRenderRequest(generation: 1, photoID: id, rawURL: url, recipe: look, quality: .interactive)
        )
        XCTAssertNotEqual(baseKey, lookKey)
        XCTAssertTrue(lookKey.contains(lookPrint))
        XCTAssertTrue(lookKey.contains(RawDecodeBackendRegistry.mappingVersion))
    }

    func testPhotoRecordIsReachableFromTheRenderDataPlane() {
        let photo = PhotoRecord(
            rawPath: "/tmp/frame.arw",
            filename: "frame.arw",
            thumbPath: "/tmp/frame-thumb.jpg",
            proxyPath: "/tmp/frame-proxy.jpg"
        )
        XCTAssertEqual(nonisolatedPhotoTierPath(photo), "/tmp/frame-proxy.jpg")
        // ensureProxy may return nil without real cache dirs — call is the compile lock.
        _ = nonisolatedEnsureProxy(for: photo, projectName: "isolation-lock")
    }

    func testOneToOneRegionMatchesDrawablePixelsAndPan() {
        let region = DevelopRenderRegion.oneToOne(
            center: CGPoint(x: 0.75, y: 0.4),
            drawableSize: CGSize(width: 1200, height: 800),
            imagePixelSize: CGSize(width: 6000, height: 4000)
        )
        XCTAssertEqual(region.width, 0.2, accuracy: 1e-9)
        XCTAssertEqual(region.height, 0.2, accuracy: 1e-9)
        XCTAssertEqual(region.x, 0.65, accuracy: 1e-9)
        XCTAssertEqual(region.y, 0.3, accuracy: 1e-9)
    }

    func testProductionRawBackendRemainsAppleOnly() {
        XCTAssertEqual(RawDecodeBackendRegistry.production.identifier, "apple-ciraw")
        let linked = RawDecodeBackendRegistry.benchmarkInventory.filter(\.linked)
        XCTAssertEqual(linked.map(\.identifier), ["apple-ciraw"])
    }

    func testCancelledRenderWaiterDoesNotBlockLatestWork() async {
        let gate = RenderGate(limit: 1)
        let first = await gate.acquire()
        XCTAssertTrue(first)

        let cancelled = Task { await gate.acquire() }
        await Task.yield()
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        XCTAssertFalse(cancelledResult)

        await gate.release()
        let latest = await gate.acquire()
        XCTAssertTrue(latest)
        await gate.release()
    }

    func testFocusedSurfaceAndSchedulerOwnershipArePinnedInSource() throws {
        let editor = try source("Lumina/Views/P0/P0SinglePhotoEditor.swift")
        XCTAssertTrue(editor.contains("One permanent Metal leaf owns this click"))
        XCTAssertTrue(editor.contains("immediateBrowseImage"))
        XCTAssertTrue(editor.contains("OrientedDisplayImage.ciImage"))
        XCTAssertTrue(editor.contains("OrientedDisplayImage.stablePresent"))
        XCTAssertFalse(editor.contains("CIImage(contentsOf:"))
        XCTAssertTrue(editor.contains(".task(id: asset.id)"))

        let scheduler = try source("Lumina/Develop/DevelopRenderScheduler.swift")
        XCTAssertTrue(scheduler.contains("visibleRenderGate"))
        XCTAssertTrue(scheduler.contains("speculativeRenderGate"))
        XCTAssertTrue(scheduler.contains("guard !speculative, visiblePhotoID == photoID"))
        XCTAssertTrue(scheduler.contains("quality: .interactive"))
        XCTAssertTrue(scheduler.contains("quality: .settled"))

        let browse = try source("Lumina/Services/BrowsePixelService.swift")
        XCTAssertTrue(browse.contains("guard !rawExtensions.contains(ext) else { return nil }"))
        XCTAssertFalse(browse.contains("precondition(!rawExtensions.contains(ext)"))
        XCTAssertTrue(browse.contains("decoded: decoded.cgImage"))
        XCTAssertTrue(browse.contains("pinnedPaths"))
        XCTAssertTrue(browse.contains("OrientedDisplayImage.cgImage"))

        let metalPool = try source("Lumina/Services/MetalPreviewPool.swift")
        XCTAssertFalse(metalPool.contains("decodeBrowseJPEG"))
        XCTAssertFalse(metalPool.contains("func upload(id: UUID, jpegPath:"))

        for path in [
            "Lumina/Views/Components/StablePhotoView.swift",
            "Lumina/Views/ProgressivePhotoWall.swift",
            "Lumina/Views/MetalBrowseCanvas.swift",
            "Lumina/ViewModels/ProjectViewModel.swift",
        ] {
            let interactiveSource = try source(path)
            XCTAssertTrue(
                interactiveSource.contains("BrowsePixelService.shared"),
                "\(path) does not use the shared browse decode owner"
            )
            XCTAssertFalse(
                interactiveSource.contains("PhotoImageCache.shared"),
                "\(path) bypasses the shared browse decode owner"
            )
        }

        let export = try source("Lumina/Services/P0AuthoritativeExportService.swift")
        XCTAssertTrue(export.contains("DevelopRenderGraph.renderExportBitmap"))
        XCTAssertTrue(export.contains("DevelopRenderGraph.exportTIFF"))

        let graph = try source("Lumina/Develop/DevelopRenderGraph.swift")
        XCTAssertTrue(graph.contains("OrientedDisplayImage.aligning"))
        XCTAssertTrue(graph.contains("OrientedDisplayImage.ciImage"))
        XCTAssertFalse(graph.contains("applyOrientationProperty"))
        XCTAssertFalse(graph.contains("CIImage(contentsOf:"))

        let metal = try source("Lumina/Develop/Lab/DevelopMetalView.swift")
        XCTAssertTrue(metal.contains("destination.isFlipped = true"))
        XCTAssertTrue(metal.contains("OrientedDisplayImage"))

        let oriented = try source("Lumina/Rendering/OrientedDisplayImage.swift")
        XCTAssertTrue(oriented.contains("CreateThumbnailWithTransform"))
        XCTAssertTrue(oriented.contains("stablePresent"))
        XCTAssertFalse(oriented.contains("applyOrientationProperty"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repoRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
