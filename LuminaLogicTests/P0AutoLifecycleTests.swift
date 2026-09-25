import XCTest
@testable import Lumina

@MainActor
final class P0AutoLifecycleTests: XCTestCase {
    private func asset(id: UUID = UUID(), stats: ImageStats? = nil) -> AssetRecord {
        AssetRecord(id: id, sourceKey: id.uuidString,
                    source: SourceReference(originalPath: "/proof/\(id).ARW", relativePath: "\(id).ARW",
                                            volumeID: "proof", availability: .available),
                    filename: "\(id).ARW", imageStats: stats)
    }

    private var stats: ImageStats {
        ImageStats(luminanceBins: Array(repeating: 32, count: ImageStats.binCount),
                   shadowClipFraction: 0, highlightClipFraction: 0, mean: 0.2)
    }

    private func session(_ assets: [AssetRecord]) -> P0SessionModel {
        let session = P0SessionModel()
        session.assets = assets
        session.shoot = ShootRecord(name: "auto-lifecycle-proof", assets: assets)
        return session
    }

    func testBusyIsImmediateAndDoubleActivationMakesOneUndo() async throws {
        let session = session([asset()])
        let started = expectation(description: "measurement started")
        var resume: CheckedContinuation<ImageStats?, Never>?
        var calls = 0
        session.applyAutoToTable { _ in
            calls += 1
            return await withCheckedContinuation { resume = $0; started.fulfill() }
        }
        let task = try XCTUnwrap(session.autoTask)
        XCTAssertNotNil(session.autoRun)
        XCTAssertFalse(session.autoButtonEnabled)
        session.applyAutoToTable { _ in XCTFail("duplicate activation"); return nil }
        await fulfillment(of: [started], timeout: 2)
        resume?.resume(returning: stats)
        await task.value
        XCTAssertEqual(calls, 1)
        XCTAssertNil(session.autoRun)
        XCTAssertEqual(session.autoReceipt?.adjusted, 1)
        XCTAssertEqual(session.undoCoordinator.stack.count, 1)
    }

    func testScopeFrozenWhileKeepsAndSelectionChange() async throws {
        var first = asset(), second = asset(stats: stats)
        first.cull = .keep
        second.cull = .reject
        let session = session([first, second])
        let started = expectation(description: "measurement started")
        var resume: CheckedContinuation<ImageStats?, Never>?
        session.applyAutoToTable { _ in
            await withCheckedContinuation { resume = $0; started.fulfill() }
        }
        let task = try XCTUnwrap(session.autoTask)
        await fulfillment(of: [started], timeout: 2)
        session.assets[0].cull = .reject
        session.assets[1].cull = .keep
        session.selectedAssetIDs = [second.id]
        resume?.resume(returning: stats)
        await task.value
        XCTAssertEqual(session.assets[0].recipeSource, .auto)
        XCTAssertEqual(session.assets[1].recipeSource, .shot)
        XCTAssertEqual(session.assets[0].cull, .reject)
        XCTAssertEqual(session.assets[1].cull, .keep)
        XCTAssertEqual(session.selectedAssetIDs, [second.id])
    }

    func testHandEditDuringMeasurementProtected() async throws {
        let session = session([asset()])
        let started = expectation(description: "measurement started")
        var resume: CheckedContinuation<ImageStats?, Never>?
        session.applyAutoToTable { _ in
            await withCheckedContinuation { resume = $0; started.fulfill() }
        }
        let task = try XCTUnwrap(session.autoTask)
        await fulfillment(of: [started], timeout: 2)
        session.assets[0].recipe = EditRecipe(exposure: 1.2)
        session.assets[0].recipeSource = .hand
        resume?.resume(returning: stats)
        await task.value
        XCTAssertEqual(session.assets[0].recipe?.exposure, 1.2)
        XCTAssertEqual(session.autoReceipt?.protected, 1)
        XCTAssertEqual(session.autoReceipt?.adjusted, 0)
        XCTAssertFalse(session.canUndo)
    }

    func testPartialMeasurementsAndMeasuredNoopHaveHonestCounts() async throws {
        var unchanged = asset(stats: stats)
        unchanged.recipe = AutoDevelop.recipe(for: unchanged, stats: stats)
        let session = session([asset(stats: stats), asset(), unchanged])
        session.applyAutoToTable { _ in nil }
        let task = try XCTUnwrap(session.autoTask)
        await task.value
        XCTAssertEqual(session.autoReceipt, P0AutoReceipt(adjusted: 1, unchanged: 1, unmeasured: 1, protected: 0, skipped: 0))
    }

    func testAllUnmeasuredDoesNotClaimUnchangedOrCreateUndo() async throws {
        let session = session([asset()])
        session.applyAutoToTable { _ in nil }
        let task = try XCTUnwrap(session.autoTask)
        await task.value
        XCTAssertEqual(session.autoReceipt, P0AutoReceipt(adjusted: 0, unchanged: 0, unmeasured: 1, protected: 0, skipped: 0))
        XCTAssertFalse(session.canUndo)
    }

    func testChangedSourceWithSameUUIDRejectsStatsAndCommit() async throws {
        let session = session([asset()])
        let started = expectation(description: "measurement started")
        var resume: CheckedContinuation<ImageStats?, Never>?
        session.applyAutoToTable { _ in
            await withCheckedContinuation { resume = $0; started.fulfill() }
        }
        let task = try XCTUnwrap(session.autoTask)
        await fulfillment(of: [started], timeout: 2)
        session.assets[0].source.originalPath = "/replacement.ARW"
        resume?.resume(returning: stats)
        await task.value
        XCTAssertNil(session.assets[0].imageStats)
        XCTAssertNil(session.assets[0].recipe)
        XCTAssertEqual(session.autoReceipt?.skipped, 1)
    }

    func testCancellationAndSameShootReopenCannotPublishStaleResult() async throws {
        let original = asset()
        let session = session([original])
        let shoot = session.shoot
        let started = expectation(description: "measurement started")
        var resume: CheckedContinuation<ImageStats?, Never>?
        session.applyAutoToTable { _ in
            await withCheckedContinuation { resume = $0; started.fulfill() }
        }
        let task = try XCTUnwrap(session.autoTask)
        await fulfillment(of: [started], timeout: 2)
        session.goHome()
        session.shoot = shoot
        session.assets = [original]
        resume?.resume(returning: stats)
        await task.value
        XCTAssertNil(session.assets[0].imageStats)
        XCTAssertNil(session.assets[0].recipe)
        XCTAssertNil(session.autoReceipt)
        XCTAssertNil(session.autoRun)
        XCTAssertFalse(session.canUndo)
    }
    func testCompletionFeedbackYieldsToBeforeSelectionFocusAndUndo() {
        let frame = asset(stats: stats)
        let session = session([frame])
        let receipt = P0AutoReceipt(adjusted: 1, unchanged: 0, unmeasured: 0, protected: 0, skipped: 0)
        session.autoReceipt = receipt
        session.showingBefore = true
        XCTAssertTrue(session.elasticHeadline.hasPrefix("before"))
        XCTAssertNil(session.autoReceipt)
        session.showingBefore = false
        session.autoReceipt = receipt
        session.selectedAssetIDs = [frame.id]
        XCTAssertTrue(session.elasticHeadline.hasPrefix("1 selected"))
        XCTAssertNil(session.autoReceipt)
        session.selectedAssetIDs = []
        session.autoReceipt = receipt
        session.focusedAssetID = frame.id
        XCTAssertNil(session.autoReceipt)
        session.applyAuto(to: [frame.id])
        session.autoReceipt = receipt
        session.undoLast()
        XCTAssertNil(session.autoReceipt)
        XCTAssertEqual(session.assets[0].recipeSource, .shot)
    }

    func testRunningFeedbackYieldsToBeforeSelectionAndSetPeek() {
        var frame = asset()
        frame.cull = .keep
        let session = session([frame])
        session.autoRun = P0AutoRun(id: UUID(), shootID: session.shoot?.id,
            contextID: session.autoContextID, targetIDs: [frame.id], scope: "all · 1",
            sources: [frame.id: P0AutoSource(frame)],
            recipeFingerprints: [frame.id: EditRecipe.neutral.valueFingerprint])
        session.showingBefore = true
        XCTAssertTrue(session.elasticHeadline.hasPrefix("before"))
        session.showingBefore = false
        session.selectedAssetIDs = [frame.id]
        XCTAssertTrue(session.elasticHeadline.hasPrefix("1 selected"))
        session.selectedAssetIDs = []
        session.route = .focus
        session.focusedAssetID = frame.id
        session.peek = .set
        XCTAssertTrue(session.elasticHeadline.contains("in the set"))
        session.peek = nil
        XCTAssertTrue(session.elasticHeadline.hasPrefix("Applying adjustments"))
        XCTAssertNotNil(session.autoRun, "temporary views must not cancel actual Auto work")
    }

    func testCommandClickRoundTripCannotResurrectCompletionReceipt() {
        let frame = asset()
        let session = session([frame])
        session.autoReceipt = P0AutoReceipt(adjusted: 1, unchanged: 0, unmeasured: 0, protected: 0, skipped: 0)
        session.clickFrame(frame.id, shift: false, command: true)
        XCTAssertTrue(session.elasticHeadline.hasPrefix("1 selected"))
        session.clickFrame(frame.id, shift: false, command: true)
        XCTAssertTrue(session.selectedAssetIDs.isEmpty)
        XCTAssertNil(session.autoReceipt)
        XCTAssertFalse(session.elasticHeadline.contains("adjusted"))
    }

    func testPendingHandGestureDuringMeasurementIsProtectedBeforeProvenanceChanges() async throws {
        let frame = asset()
        let session = session([frame])
        session.focusedAssetID = frame.id
        let started = expectation(description: "measurement started")
        var resume: CheckedContinuation<ImageStats?, Never>?
        session.applyAutoToTable { _ in
            await withCheckedContinuation { resume = $0; started.fulfill() }
        }
        let task = try XCTUnwrap(session.autoTask)
        await fulfillment(of: [started], timeout: 2)
        session.beginEditGesture(for: frame.id)
        session.scrubEdit { $0.exposure = 1.2 }
        resume?.resume(returning: stats)
        await task.value
        XCTAssertEqual(session.recipe(for: frame.id).exposure, 1.2)
        XCTAssertEqual(session.autoReceipt?.protected, 1)
        XCTAssertEqual(session.autoReceipt?.adjusted, 0)
        XCTAssertEqual(session.undoCoordinator.stack.count, 1, "only the user's gesture commits")
    }

}
