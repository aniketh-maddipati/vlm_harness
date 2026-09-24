import CoreGraphics
import XCTest
@testable import Lumina

final class ElasticViewportRevealTests: XCTestCase {
    func testVisibleAndViewportSpanningTargetsDoNotMove() {
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertFalse(ElasticViewportReveal.needsReveal(CGRect(x: 40, y: 20, width: 120, height: 90), in: viewport))
        XCTAssertFalse(ElasticViewportReveal.needsReveal(CGRect(x: 0, y: -50, width: 800, height: 700), in: viewport))
    }

    func testTargetsBeyondEachEdgeNeedReveal() {
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        for target in [CGRect(x: -1, y: 30, width: 100, height: 90),
                       CGRect(x: 701, y: 30, width: 100, height: 90),
                       CGRect(x: 30, y: -1, width: 100, height: 90),
                       CGRect(x: 30, y: 511, width: 100, height: 90)] {
            XCTAssertTrue(ElasticViewportReveal.needsReveal(target, in: viewport))
        }
    }

    func testAnchorUsesFirstVisiblePhotoRatherThanFocusedOrOffscreenPhoto() throws {
        let first = UUID(), second = UUID(), offscreen = UUID()
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        let anchor = try XCTUnwrap(ElasticViewportReveal.anchor(frames: [
            offscreen: CGRect(x: 0, y: -200, width: 120, height: 90),
            second: CGRect(x: 200, y: 100, width: 120, height: 90),
            first: CGRect(x: 40, y: 100, width: 120, height: 90)
        ], viewport: viewport))
        XCTAssertEqual(anchor.id, first)
        XCTAssertEqual(anchor.position, 100.0 / 510.0, accuracy: 0.00001)
    }

    func testEmptyOrClippedAnchorIsBounded() {
        let id = UUID()
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertNil(ElasticViewportReveal.anchor(frames: [:], viewport: viewport))
        XCTAssertEqual(ElasticViewportReveal.anchor(frames: [id: CGRect(x: 40, y: -20, width: 120, height: 90)], viewport: viewport)?.position, 0)
        XCTAssertFalse(ElasticViewportReveal.needsReveal(.zero, in: viewport))
    }

    func testInitialRequestRevealsLatePhotoWithoutAFocusChange() {
        let id = UUID()
        var request = ElasticViewportReveal.Request(id: id, expectedSize: CGSize(width: 96, height: 72))
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 92)
        XCTAssertEqual(request.resolve(frames: [:], viewport: viewport), .wait)
        XCTAssertEqual(request.resolve(frames: [id: CGRect(x: 1200, y: 10, width: 96, height: 72)], viewport: viewport), .reveal(id, nil))
    }

    func testFocusGrowthWaitsForNewTileGeometry() {
        let id = UUID()
        var request = ElasticViewportReveal.Request(id: id, expectedSize: CGSize(width: 96, height: 72))
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 92)
        XCTAssertEqual(request.resolve(frames: [id: CGRect(x: 720, y: 10, width: 72, height: 54)], viewport: viewport), .wait)
        XCTAssertEqual(request.resolve(frames: [id: CGRect(x: 720, y: 10, width: 96, height: 72)], viewport: viewport), .reveal(id, nil))
    }

    func testContainerRequestIgnoresUnrelatedLayoutThenCompletes() {
        let id = UUID()
        var request = ElasticViewportReveal.Request(id: id, containerID: "target")
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertEqual(request.resolve(frames: [:], viewport: viewport), .wait)
        XCTAssertEqual(request.resolve(frames: [:], viewport: viewport, realizedContainers: ["other"]), .wait)
        XCTAssertEqual(request.resolve(frames: [:], viewport: viewport, realizedContainers: ["target"]), .finished)
        XCTAssertEqual(request.resolve(frames: [id: CGRect(x: 30, y: 30, width: 100, height: 90)], viewport: viewport), .finished)
    }

    func testRestorePreservesRequestedPositionEvenIfTargetIsVisible() {
        let id = UUID()
        var request = ElasticViewportReveal.Request(id: id, position: 0.25)
        XCTAssertEqual(request.resolve(frames: [id: CGRect(x: 30, y: 30, width: 100, height: 90)],
                                       viewport: CGRect(x: 0, y: 0, width: 800, height: 600)), .reveal(id, 0.25))
    }


    func testGeometryBeforeFocusCallbackCanResolveImmediately() {
        let id = UUID()
        let frames = [id: CGRect(x: 780, y: 10, width: 96, height: 72)]
        var request = ElasticViewportReveal.Request(id: id, expectedSize: CGSize(width: 96, height: 72))
        XCTAssertEqual(request.resolve(frames: frames, viewport: CGRect(x: 0, y: 0, width: 800, height: 92)), .reveal(id, nil))
    }

    func testContentChangeWithIdenticalGeometryFinishesWithoutAnotherPreference() {
        let id = UUID()
        let frames = [id: CGRect(x: 100, y: 10, width: 96, height: 72)]
        var request = ElasticViewportReveal.Request(id: id, expectedSize: CGSize(width: 96, height: 72))
        XCTAssertEqual(request.resolve(frames: frames, viewport: CGRect(x: 0, y: 0, width: 800, height: 92)), .finished)
    }

}
