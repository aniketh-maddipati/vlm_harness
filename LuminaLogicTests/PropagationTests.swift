import XCTest
@testable import Lumina

@MainActor
final class PropagationTests: XCTestCase {

    func testDefaultRingIsRow() {
        var state = PropagationState(
            referencePhotoID: UUID(),
            referenceGroupID: "g1",
            referenceFrame: "8288"
        )
        XCTAssertEqual(state.ring, .row)
    }

    func testExceptionPersistenceThroughRestage() {
        let excluded = UUID()
        var state = PropagationState(
            referencePhotoID: UUID(),
            referenceGroupID: "g1",
            referenceFrame: "8288",
            excludedIDs: [excluded]
        )
        state.excludedIDs = [excluded]
        let restaged = PropagationState(
            ring: .row,
            referencePhotoID: UUID(),
            referenceGroupID: "g2",
            referenceFrame: "8289",
            excludedIDs: state.excludedIDs
        )
        XCTAssertEqual(restaged.excludedIDs, [excluded])
    }

    func testA1AtShootRingWithExclusions() {
        let snapshot = StagingCopySnapshot(
            scopeCount: 10,
            excludedCount: 2,
            rowIndex: 1,
            laneTimestamp: "18:17",
            ring: .shoot
        )
        let header = CopyContract.stagedHeader(snapshot)
        let banner = CopyContract.adaptBanner(snapshot)
        let receipt = CopyContract.adaptedReceipt(count: snapshot.scopeCount)
        XCTAssertTrue(A1Invariant.validate(header: header, banner: banner, receipt: receipt, snapshot: snapshot))
    }

    func testSelectionRingDistinctFromTableHalo() {
        HiFiTokens.Ring.assertDistinctSelectionAndHalo()
        let selectionHex = "2E2E2C"
        let haloHex = String(format: "%02X%02X%02X", 255, 236, 205)
        XCTAssertNotEqual(selectionHex, haloHex)
    }
}
