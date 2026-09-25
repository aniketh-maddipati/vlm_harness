import XCTest
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
@testable import Lumina

@MainActor
final class P0OrderedExportTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ordered-export-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func asset(_ path: String, date: Date? = nil, cull: CullDecision = .keep) -> AssetRecord {
        AssetRecord(id: UUID(), sourceKey: UUID().uuidString,
                    source: SourceReference(originalPath: path, relativePath: URL(fileURLWithPath: path).lastPathComponent, volumeID: "test", availability: .available),
                    filename: URL(fileURLWithPath: path).lastPathComponent, cull: cull, capturedAt: date)
    }
    private func plan(_ items: [AssetRecord], settings: P0ExportSettings = .init()) throws -> P0ExportPlan {
        try P0ExportPlan.make(shootID: UUID(), assets: items, order: [], settings: settings)
    }
    private func original(in folder: URL, orientation: Int = 1) throws -> URL {
        let url = folder.appendingPathComponent(UUID().uuidString + ".png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 2400,
                                            space: DevelopColorPolicy.exportJPEGColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Spatial color/detail and translucent pixels expose treatment/orientation
        // differences that a uniform fixture cannot show.
        for y in stride(from: 0, to: 400, by: 10) {
            for x in stride(from: 0, to: 600, by: 10) {
                context.setFillColor(CGColor(red: CGFloat(x % 230) / 255, green: CGFloat(y % 190) / 255,
                                             blue: (x + y) % 20 == 0 ? 0.2 : 0.7, alpha: 0.5))
                context.fill(CGRect(x: x, y: y, width: 10, height: 10))
            }
        }
        let bitmap = try XCTUnwrap(context.makeImage())
        let sink = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(sink, bitmap, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        return url
    }

    func testOrderDeduplicatesAndSnapshotsWithMissingDatesLast() throws {
        var a = asset("/original/same.raw", date: Date(timeIntervalSince1970: 20))
        let b = asset("/other/same.raw", date: Date(timeIntervalSince1970: 10))
        let c = asset("/original/missing.raw")
        let d = asset("/original/equal.raw", date: b.capturedAt)
        let excluded = asset("/original/rejected.raw", cull: .reject)
        a.recipe = .neutral
        let frozen = try P0ExportPlan.make(shootID: UUID(), assets: [a, c, b, d, excluded], order: [a.id, a.id, excluded.id, UUID()], settings: .init())
        XCTAssertEqual(frozen.items.map(\.assetID), [a.id, b.id, d.id, c.id])
        XCTAssertEqual(Set(frozen.items.map(\.filename)).count, 4)
        a.recipe = .neutral.updating { $0.exposure = 2 }
        XCTAssertEqual(frozen.items[0].recipe, .neutral)
        XCTAssertTrue(frozen.items[0].filename.hasPrefix("0001_"))
    }

    func testLockNoClobberAndUnownedTemporaryPreserved() throws {
        let destination = try folder()
        let p = try plan([asset("/source/test.png")])
        let store = try P0ExportJobStore.create(plan: p, destination: destination)
        XCTAssertThrowsError(try P0ExportJobStore(root: store.root))
        let foreign = store.root.appendingPathComponent(".item-0.partial")
        try Data("foreign".utf8).write(to: foreign)
        try store.recover()
        XCTAssertEqual(try Data(contentsOf: foreign), Data("foreign".utf8))
        let target = store.root.appendingPathComponent(p.items[0].filename)
        try Data("existing".utf8).write(to: target)
        try store.update(0) { $0.state = .rendering }
        XCTAssertThrowsError(try store.publish(0, bytes: Data("new".utf8)))
        XCTAssertEqual(try Data(contentsOf: target), Data("existing".utf8))
        XCTAssertThrowsError(try store.recover())
    }

    func testRecoveryAfterRenameRequiresExactReceiptChecksum() throws {
        let destination = try folder()
        let p = try plan([asset("/source/test.png")])
        var store: P0ExportJobStore? = try P0ExportJobStore.create(plan: p, destination: destination)
        let root = try XCTUnwrap(store).root
        let bytes = Data("published pixels".utf8)
        let checksum = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try store?.update(0) { $0.state = .ready; $0.outputHash = checksum }
        try bytes.write(to: root.appendingPathComponent(p.items[0].filename))
        store = nil
        let resumed = try P0ExportJobStore(root: root)
        try resumed.recover()
        XCTAssertEqual(resumed.summary().completed, 1)
        try Data("replaced".utf8).write(to: root.appendingPathComponent(p.items[0].filename))
        XCTAssertThrowsError(try resumed.recover())
    }

    func testRemovedOrReplacedRootStopsPublication() throws {
        let destination = try folder()
        let store = try P0ExportJobStore.create(plan: plan([asset("/source/test.png")]), destination: destination)
        try store.update(0) { $0.state = .rendering }
        let moved = destination.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: store.root, to: moved)
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.publish(0, bytes: Data("pixels".utf8)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.root.path), [])
    }

    func testProductionJPEGProfileGeometryAndNoUpscale() async throws {
        let root = try folder()
        let source = try original(in: root)
        let before = try P0ExportJobStore.hash(source)
        var recipe = EditRecipe.neutral
        recipe.straightenDegrees = 90
        let full = try XCTUnwrap(awaitBitmap: await DevelopRenderGraph.renderExportBitmap(rawURL: source, photoID: UUID(), recipe: recipe, settings: .init()))
        XCTAssertEqual(full.width, 400)
        XCTAssertEqual(full.height, 600)
        let settings = P0ExportSettings(longEdge: 300)
        let resized = try XCTUnwrap(awaitBitmap: await DevelopRenderGraph.renderExportBitmap(rawURL: source, photoID: UUID(), recipe: recipe, settings: settings))
        XCTAssertEqual(resized.width, 200)
        XCTAssertEqual(resized.height, 300)
        let bytes = try XCTUnwrap(DevelopRenderGraph.exportJPEGData(cgImage: resized, quality: settings.quality))
        XCTAssertTrue(DevelopRenderGraph.validateExport(bytes: bytes, bitmap: resized, settings: settings))
        let bigger = try XCTUnwrap(awaitBitmap: await DevelopRenderGraph.renderExportBitmap(rawURL: source, photoID: UUID(), recipe: .neutral, settings: .init(longEdge: 2048)))
        XCTAssertEqual(bigger.width, 600)
        XCTAssertEqual(bigger.height, 400)
        XCTAssertEqual(try P0ExportJobStore.hash(source), before)
    }

    func testProductionPartialFailureAndRetryPreserveCompletedOutput() async throws {
        let root = try folder()
        let source = try original(in: root)
        let p = try plan([asset(source.path), asset(root.appendingPathComponent("missing.png").path)])
        let result = try await P0AuthoritativeExportService.export(plan: p, to: root) { _ in }
        XCTAssertEqual(result.completed, 1)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.total, 2)
        let output = result.root.appendingPathComponent(p.items[0].filename)
        let hash = try P0ExportJobStore.hash(output)
        let retry = try await P0AuthoritativeExportService.resume(root: result.root) { _ in }
        XCTAssertEqual(retry.completed, 1)
        XCTAssertEqual(retry.failed, 1)
        XCTAssertEqual(try P0ExportJobStore.hash(output), hash)
    }
    func testProcessedNonneutralTreatmentMatchesPreviewOrExplicitlyFails() async throws {
        let root = try folder()
        let source = try original(in: root)
        let recipes = [
            EditRecipe.neutral.updating { $0.exposure = 1.2; $0.temperature = 5200; $0.tint = 15; $0.contrast = 12 },
            EditRecipe.neutral.updating { $0.sharpness = 70; $0.luminanceNR = 40 },
        ]
        for recipe in recipes {
            let preview = await DevelopRenderGraph.render(RawRenderRequest(generation: 1, photoID: UUID(), rawURL: source, recipe: recipe, quality: .settled, longEdgeCap: 0))
            let output = await DevelopRenderGraph.renderExportBitmap(rawURL: source, photoID: UUID(), recipe: recipe, settings: .init())
            if preview.usedProxyFallback && (recipe.sharpness != 0 || recipe.luminanceNR != 0) {
                XCTAssertNil(output, "Unsupported RAW controls must never silently disappear")
            } else {
                let bitmap = try XCTUnwrap(output)
                let image = try XCTUnwrap(preview.ciImage)
                let opaque = image.composited(over: CIImage(color: .black).cropped(to: image.extent))
                let expected = try XCTUnwrap(DevelopRenderGraph.sharedExportContext.createCGImage(opaque, from: opaque.extent, format: .RGBA8, colorSpace: DevelopColorPolicy.exportJPEGColorSpace))
                XCTAssertEqual(bitmap.width, expected.width)
                XCTAssertEqual(bitmap.height, expected.height)
                XCTAssertEqual(bitmap.dataProvider?.data as Data?, expected.dataProvider?.data as Data?)
            }
        }
    }

    func testCropAndEXIFOrientationPreservedOnce() async throws {
        let root = try folder()
        let source = try original(in: root, orientation: 6)
        let recipe = EditRecipe.neutral.updating { $0.crop = EditCrop(x: 0, y: 0, width: 0.5, height: 0.5) }
        let bitmap = try XCTUnwrap(awaitBitmap: await DevelopRenderGraph.renderExportBitmap(rawURL: source, photoID: UUID(), recipe: recipe, settings: .init()))
        XCTAssertEqual(bitmap.width, 200)
        XCTAssertEqual(bitmap.height, 300)
    }

    func testCancellationAfterPublicationKeepsCompletedAndCancelsRemaining() async throws {
        let root = try folder()
        let source = try original(in: root)
        let p = try plan([asset(source.path), asset(source.path), asset(source.path)])
        let task = Task {
            try await P0AuthoritativeExportService.export(plan: p, to: root) { summary in
                if summary.completed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        let summary = try await task.value
        XCTAssertEqual(summary.completed, 1)
        XCTAssertEqual(summary.cancelled, 2)
        XCTAssertEqual(summary.total, 3)
        let resumed = try await P0AuthoritativeExportService.resume(root: summary.root) { _ in }
        XCTAssertTrue(resumed.allCompleted)
    }

    func testSourceChangeOnRetryFailsAndLocatorMismatchDoesNotMutate() async throws {
        let root = try folder()
        let source = try original(in: root)
        let p = try plan([asset(source.path)])
        var store: P0ExportJobStore? = try P0ExportJobStore.create(plan: p, destination: root)
        let jobRoot = try XCTUnwrap(store).root
        let originalHash = try P0ExportJobStore.hash(source)
        try store?.update(0) { $0.state = .cancelled; $0.sourceHash = originalHash }
        store = nil
        let saved = try Data(contentsOf: jobRoot.appendingPathComponent("export.json"))
        do {
            _ = try await P0AuthoritativeExportService.resume(root: jobRoot, expectedJobID: UUID(), expectedShootID: p.shootID) { _ in }
            XCTFail("Mismatched job must be rejected")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: jobRoot.appendingPathComponent("export.json")), saved)
        try Data("changed original".utf8).write(to: source)
        let summary = try await P0AuthoritativeExportService.resume(root: jobRoot) { _ in }
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.completed, 0)
        XCTAssertTrue(summary.firstFailure?.contains("original changed") == true)
    }

    func testDirectShootTransitionDetachesExportAndZeroKeepJobCanResume() throws {
        let root = try folder()
        let session = P0SessionModel()
        session.shoot = ShootRecord(name: "A")
        session.assets = [asset(root.appendingPathComponent("missing.png").path)]
        session.exportKept(to: root)
        XCTAssertTrue(session.isExporting)
        session.openShoot(named: "nonexistent-" + UUID().uuidString)
        XCTAssertFalse(session.isExporting)
        XCTAssertNil(session.exportSummary)
        XCTAssertNil(session.exportStatusLine)
        session.goHome()
        session.shoot = ShootRecord(name: "B")
        let saved = IngestPreferences.lastExportJob
        IngestPreferences.lastExportJob = nil
        session.shoot = nil
        XCTAssertFalse(session.canResumeExport)
        session.shoot = ShootRecord(name: "B")
        IngestPreferences.lastExportJob = .init(root: root, jobID: UUID(), shootID: UUID())
        XCTAssertFalse(session.canResumeExport)
        defer { IngestPreferences.lastExportJob = saved }
        IngestPreferences.lastExportJob = .init(root: root, jobID: UUID(), shootID: session.shoot!.id)
        XCTAssertEqual(session.exportCount, 0)
        XCTAssertTrue(session.canResumeExport)
    }

    func testFocusedExportControlsOwnTabArrowsAndSpaceButNotSettingsChord() throws {
        let session = P0SessionModel()
        let a = asset("/test/a.png"), b = asset("/test/b.png")
        session.assets = [a, b]
        session.route = .time
        session.setFocus(a.id)
        session.openPeek(.related)
        session.setShowingBefore(true)
        session.setHoldingClipping(true)
        session.exportControlsFocused = true
        XCTAssertNil(session.peek)
        XCTAssertFalse(session.showingBefore)
        XCTAssertFalse(session.holdingClipping)
        let coordinator = P0KeyRoutingRepresentable.Coordinator(session: session)
        for code: UInt16 in [48, 49, 123, 124, 125, 126] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            XCTAssertTrue(coordinator.handleKeyDown(event) === event)
            XCTAssertTrue(coordinator.handleKeyUp(event) === event)
            XCTAssertEqual(session.focusedAssetID, a.id)
            XCTAssertNil(session.peek)
            XCTAssertFalse(session.showingBefore)
        }
        let chord = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0, windowNumber: 0, context: nil, characters: "e", charactersIgnoringModifiers: "e", isARepeat: false, keyCode: 14))
        XCTAssertNil(coordinator.handleKeyDown(chord))
        XCTAssertTrue(session.exportSettingsVisible)
    }

    func testOversizedManifestRejectedBeforeAnyOutputAndInvalidRawFails() async throws {
        let root = try folder()
        let huge = try plan([asset("/" + String(repeating: "a", count: 16_000_001))])
        XCTAssertThrowsError(try P0ExportJobStore.create(plan: huge, destination: root))
        let raw = root.appendingPathComponent("broken.dng")
        try Data("invalid raw".utf8).write(to: raw)
        let output = await DevelopRenderGraph.renderExportBitmap(rawURL: raw, photoID: UUID(), recipe: .neutral, settings: .init())
        XCTAssertNil(output)
    }

}

private func XCTUnwrap(awaitBitmap: CGImage?, file: StaticString = #filePath, line: UInt = #line) throws -> CGImage {
    try XCTUnwrap(awaitBitmap, file: file, line: line)
}
