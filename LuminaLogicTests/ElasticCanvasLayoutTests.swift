import XCTest
@testable import Lumina

@MainActor
final class ElasticCanvasLayoutTests: XCTestCase {
    func testStepsMatchSealedTokens() {
        XCTAssertEqual(ElasticCanvasLayout.steps, HiFiTokens.Grid.elasticityStepsPx)
        XCTAssertEqual(ElasticCanvasLayout.steps, [210, 140, 96, 64])
        XCTAssertEqual(ElasticCanvasLayout.stripTrackHeight, HiFiTokens.Grid.stripEvidenceHeight)
        XCTAssertEqual(ElasticCanvasLayout.stripTrackHeight, 90)
    }

    func testPeripheryIsQuantizedAndDistantFirst() {
        XCTAssertEqual(ElasticCanvasLayout.peripheryLongEdge(distanceFromFocus: 0), 90)
        XCTAssertEqual(ElasticCanvasLayout.peripheryLongEdge(distanceFromFocus: 1), 210)
        XCTAssertEqual(ElasticCanvasLayout.peripheryLongEdge(distanceFromFocus: 2), 140)
        XCTAssertEqual(ElasticCanvasLayout.peripheryLongEdge(distanceFromFocus: 3), 96)
        XCTAssertEqual(ElasticCanvasLayout.peripheryLongEdge(distanceFromFocus: 4), 64)
        XCTAssertEqual(
            ElasticCanvasLayout.peripheryLongEdge(distanceFromFocus: 12),
            ElasticCanvasLayout.peripheryLongEdge(distanceFromFocus: 4)
        )
    }

    func testRestStatesAreExactTokenSteps() {
        let observed = (0...8).map { ElasticCanvasLayout.peripheryLongEdge(distanceFromFocus: $0) }
        let allowed: Set<CGFloat> = [90, 210, 140, 96, 64]
        for value in observed {
            XCTAssertTrue(allowed.contains(value), "in-between rest size \(value)")
        }
    }

    func testFocusDoesNotMoveWhenNeighborDistanceChanges() {
        let focus = ElasticCanvasLayout.peripheryLongEdge(distanceFromFocus: 0)
        XCTAssertEqual(focus, ElasticCanvasLayout.peripheryLongEdge(distanceFromFocus: 0))
        XCTAssertEqual(ElasticCanvasLayout.distance(from: 7, focus: 7), 0)
        XCTAssertEqual(ElasticCanvasLayout.distance(from: 4, focus: 7), 3)
    }

    func testPeripheryDimIsTokenAndNeverAbsent() {
        XCTAssertEqual(ElasticCanvasLayout.peripheryDimOpacity, HiFiTokens.Color.rejectDimOpacity)
        XCTAssertEqual(ElasticCanvasLayout.peripheryDimOpacity, 0.45)
        XCTAssertEqual(ElasticCanvasLayout.plateOpacity(distanceFromFocus: 0), 1)
        XCTAssertEqual(ElasticCanvasLayout.plateOpacity(distanceFromFocus: 1), 0.45)
        XCTAssertEqual(ElasticCanvasLayout.plateOpacity(distanceFromFocus: 12), 0.45)
        XCTAssertEqual(ElasticCanvasLayout.plateOpacity(distanceFromFocus: 0, rejected: true), 0.45)
        XCTAssertGreaterThan(ElasticCanvasLayout.plateOpacity(distanceFromFocus: 4), 0)
    }

    func testInspectNeighborRangeKeepsDistantFrames() {
        XCTAssertEqual(ElasticCanvasLayout.inspectNeighborRange(focusIndex: 20, count: 40), 6..<35)
        XCTAssertEqual(ElasticCanvasLayout.inspectNeighborRange(focusIndex: 0, count: 8), 0..<8)
        XCTAssertEqual(ElasticCanvasLayout.inspectNeighborRange(focusIndex: nil, count: 40), 0..<16)
        XCTAssertEqual(ElasticCanvasLayout.inspectNeighborRange(focusIndex: 0, count: 0), 0..<0)
    }
}
