import XCTest
@testable import Lumina

@MainActor
final class DevelopStagingTests: XCTestCase {

    func testBatchKeyFilterIgnoresAutoRepeat() {
        XCTAssertTrue(BatchKeyFilter.shouldIgnore(isARepeat: true))
        XCTAssertFalse(BatchKeyFilter.shouldIgnore(isARepeat: false))
    }

    func testDistinctAutoSuggestionsProduceDistinctProposals() {
        let dark = AutoDevelop.Suggestion(
            exposure: -0.8, contrast: 10, highlights: -20, shadows: 15, vibrance: 5, kelvin: 5200, tint: 2
        )
        let bright = AutoDevelop.Suggestion(
            exposure: 0.6, contrast: 5, highlights: -5, shadows: 0, vibrance: 12, kelvin: 6800, tint: -3
        )
        let base = DevelopRecipe.neutral
        let darkOffsets = DevelopAdjustments.from(autoSuggestion: dark, base: base)
        let brightOffsets = DevelopAdjustments.from(autoSuggestion: bright, base: base)
        let pDark = base.applying(darkOffsets)
        let pBright = base.applying(brightOffsets)
        XCTAssertNotEqual(pDark.exposure, pBright.exposure, accuracy: 1e-9)
        XCTAssertNotEqual(pDark.temperature, pBright.temperature, accuracy: 1e-9)
    }

    func testDevelopBannerA1ScopeAlignment() {
        let snapshot = StagingCopySnapshot(scopeCount: 1, isDevelop: true)
        let header = CopyContract.stagedHeader(snapshot)
        let banner = CopyContract.developBanner(count: snapshot.scopeCount)
        XCTAssertTrue(A1Invariant.validate(header: header, banner: banner, receipt: banner, snapshot: snapshot))
    }

    func testStagedActionDevelopFlag() {
        let action = StagedAction.develop(proposals: [UUID(): .neutral])
        XCTAssertTrue(action.isDevelopStaging)
        XCTAssertFalse(StagedAction.treat(.neutral).isDevelopStaging)
    }
}
