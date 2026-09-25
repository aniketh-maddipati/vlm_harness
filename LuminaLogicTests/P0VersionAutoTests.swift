import XCTest
@testable import Lumina

@MainActor
final class P0VersionAutoTests: XCTestCase {
    private var stats: ImageStats {
        ImageStats(luminanceBins: Array(repeating: 32, count: ImageStats.binCount),
                   shadowClipFraction: 0, highlightClipFraction: 0, mean: 0.2)
    }

    private func session() -> P0SessionModel {
        let session = P0SessionModel()
        let id = UUID()
        session.assets = [AssetRecord(id: id, sourceKey: id.uuidString,
            source: SourceReference(originalPath: "/proof/\(id).ARW", relativePath: "\(id).ARW",
                                    volumeID: "proof", availability: .available), filename: "proof.ARW")]
        session.shoot = ShootRecord(name: "version-auto-proof", assets: session.assets)
        session.focusedAssetID = id
        return session
    }

    private func suspended() async throws -> (P0SessionModel, Task<Void, Never>, CheckedContinuation<ImageStats?, Never>) {
        let session = session()
        let started = expectation(description: "measurement started")
        var resume: CheckedContinuation<ImageStats?, Never>?
        session.pickVersion(2, for: session.assets[0].id) { _ in
            await withCheckedContinuation { resume = $0; started.fulfill() }
        }
        let task = try XCTUnwrap(session.versionAutoTask)
        XCTAssertEqual(session.versionAutoAssetID, session.assets[0].id)
        await fulfillment(of: [started], timeout: 2)
        return (session, task, try XCTUnwrap(resume))
    }

    func testMeasuredVersionAppliesAndEndsBusy() async throws {
        let (session, task, resume) = try await suspended()
        session.pickVersion(2, for: session.assets[0].id) { _ in XCTFail("duplicate request"); return nil }
        resume.resume(returning: stats)
        await task.value
        XCTAssertNil(session.versionAutoAssetID)
        XCTAssertEqual(session.assets[0].recipeSource, .auto)
        XCTAssertEqual(session.versionAutoStatus, "Adjustments applied to this photo")
        XCTAssertEqual(session.undoCoordinator.stack.count, 1)
    }

    func testUnmeasuredVersionHasFeedbackAndNoMutation() async throws {
        let (session, task, resume) = try await suspended()
        resume.resume(returning: nil)
        await task.value
        XCTAssertNil(session.versionAutoAssetID)
        XCTAssertEqual(session.versionAutoStatus, "Adjustments unavailable · no measurements")
        XCTAssertNil(session.assets[0].recipe)
        XCTAssertFalse(session.canUndo)
    }

    func testLaterShotChoiceWinsOverSuspendedAuto() async throws {
        let (session, task, resume) = try await suspended()
        session.pickVersion(1, for: session.assets[0].id)
        resume.resume(returning: stats)
        await task.value
        XCTAssertEqual(session.assets[0].recipeSource, .shot)
        XCTAssertEqual(session.recipe(for: session.assets[0].id).valueFingerprint, EditRecipe.neutral.valueFingerprint)
        XCTAssertNil(session.assets[0].imageStats)
        XCTAssertNil(session.versionAutoAssetID)
    }

    func testFocusAwayAndBackInvalidatesOldRequest() async throws {
        let (session, task, resume) = try await suspended()
        let id = session.assets[0].id
        session.focusedAssetID = nil
        session.focusedAssetID = id
        resume.resume(returning: stats)
        await task.value
        XCTAssertNil(session.assets[0].recipe)
        XCTAssertNil(session.assets[0].imageStats)
        XCTAssertNil(session.versionAutoAssetID)
    }

    func testHandEditWinsOverSuspendedAuto() async throws {
        let (session, task, resume) = try await suspended()
        session.applyDevelopEdit(label: "Exposure") { $0.exposure = 1.2 }
        resume.resume(returning: stats)
        await task.value
        XCTAssertEqual(session.assets[0].recipe?.exposure, 1.2)
        XCTAssertEqual(session.assets[0].recipeSource, .hand)
        XCTAssertNil(session.versionAutoAssetID)
    }

    func testReopenedSameUUIDCannotReceiveOldMeasurement() async throws {
        let (session, task, resume) = try await suspended()
        let shoot = session.shoot, assets = session.assets
        session.goHome()
        session.shoot = shoot
        session.assets = assets
        resume.resume(returning: stats)
        await task.value
        XCTAssertNil(session.assets[0].imageStats)
        XCTAssertNil(session.assets[0].recipe)
        XCTAssertNil(session.versionAutoStatus)
    }

    func testSourceAndRecipeGuardsRejectDirectReplacement() async throws {
        let (session, task, resume) = try await suspended()
        session.assets[0].source.originalPath = "/changed-source.ARW"
        resume.resume(returning: stats)
        await task.value
        XCTAssertNil(session.assets[0].imageStats)
        XCTAssertNil(session.assets[0].recipe)
        XCTAssertNil(session.versionAutoAssetID)

        let (other, otherTask, otherResume) = try await suspended()
        other.assets[0].recipe = EditRecipe(exposure: 0.8)
        otherResume.resume(returning: stats)
        await otherTask.value
        XCTAssertEqual(other.assets[0].recipe?.exposure, 0.8)
        XCTAssertNil(other.versionAutoAssetID)
    }

    func testPendingHandGestureIsFlushedBeforeVersionCache() {
        let session = session()
        let id = session.assets[0].id
        session.beginEditGesture(for: id)
        session.scrubEdit { $0.exposure = 1.3 }
        session.pickVersion(1, for: id)
        XCTAssertEqual(session.assets[0].handRecipe?.exposure, 1.3)
        session.pickVersion(3, for: id)
        XCTAssertEqual(session.assets[0].recipe?.exposure, 1.3)
    }
    func testRouteExitCancelsPendingPerPhotoAuto() async throws {
        let (session, task, resume) = try await suspended()
        session.route = .time
        resume.resume(returning: stats)
        await task.value
        XCTAssertNil(session.assets[0].recipe)
        XCTAssertNil(session.versionAutoAssetID)
    }

    func testPerPhotoCompletionClearsOnCommandClickAndBefore() {
        let session = session()
        let id = session.assets[0].id
        session.versionAutoStatus = "Adjustments applied to this photo"
        session.clickFrame(id, shift: false, command: true)
        session.clickFrame(id, shift: false, command: true)
        XCTAssertNil(session.versionAutoStatus)
        session.versionAutoStatus = "Adjustments applied to this photo"
        session.showingBefore = true
        XCTAssertNil(session.versionAutoStatus)
        XCTAssertTrue(session.elasticHeadline.hasPrefix("before"))
    }

}
