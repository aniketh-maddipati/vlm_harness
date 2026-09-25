import XCTest
@testable import Lumina

final class FocusZoomTests: XCTestCase {
    private let box = CGSize(width: 800, height: 600)

    func testPinchKeepsThePointUnderTheFingers() {
        var zoom = FocusZoom()
        let finger = CGPoint(x: 600, y: 180)
        let before = zoom.contentFraction(at: finger, in: box)
        zoom.magnify(by: 0.4, at: finger, in: box, maxZoom: 4, rubber: false)
        let after = zoom.contentFraction(at: finger, in: box)
        XCTAssertEqual(after.x, before.x, accuracy: 0.0001)
        XCTAssertEqual(after.y, before.y, accuracy: 0.0001)
        XCTAssertGreaterThan(zoom.zoom, 1)
    }

    func testZoomOutStopsAtFit() {
        var zoom = FocusZoom()
        zoom.magnify(by: 1, at: CGPoint(x: 400, y: 300), in: box, maxZoom: 4, rubber: false)
        zoom.magnify(by: -0.9, at: CGPoint(x: 100, y: 80), in: box, maxZoom: 4, rubber: false)
        XCTAssertEqual(zoom.zoom, FocusZoom.fit, accuracy: 0.0001)
        XCTAssertEqual(zoom.pan, .zero)
    }

    func testPanStaysInsideThePicture() {
        var zoom = FocusZoom()
        zoom.magnify(by: 1, at: CGPoint(x: 400, y: 300), in: box, maxZoom: 4, rubber: false)
        zoom.pan(by: CGSize(width: 5000, height: -5000), in: box, rubber: false)
        let excessX = (box.width * zoom.zoom - box.width) / 2
        let excessY = (box.height * zoom.zoom - box.height) / 2
        XCTAssertEqual(zoom.pan.width, excessX, accuracy: 0.001)
        XCTAssertEqual(zoom.pan.height, -excessY, accuracy: 0.001)
    }

    func testRubberBandCannotLeaveTheSlack() {
        var zoom = FocusZoom()
        zoom.magnify(by: 20, at: CGPoint(x: 400, y: 300), in: box, maxZoom: 2, rubber: true)
        XCTAssertLessThan(zoom.zoom, 2 + FocusZoom.rubberSlack)
        zoom.settle(in: box, maxZoom: 2)
        XCTAssertEqual(zoom.zoom, 2, accuracy: 0.0001)
    }

    func testSharperFrameRebasesZoomSoTheViewedPointStays() {
        var zoom = FocusZoom()
        let finger = CGPoint(x: 640, y: 120)
        zoom.magnify(by: 0.5, at: finger, in: box, maxZoom: 8, rubber: false)
        let panBefore = zoom.pan
        let zoomBefore = zoom.zoom
        zoom.rebase(from: CGSize(width: 1920, height: 1280), to: CGSize(width: 3840, height: 2560))
        // Pan stays in points. The present fit shrinks by the same ratio zoom grows,
        // so the picture does not move on screen.
        XCTAssertEqual(zoom.zoom, zoomBefore * 2, accuracy: 0.0001)
        XCTAssertEqual(zoom.pan, panBefore)
    }

    func testTwoFingerDoubleTapTogglesAroundTheFinger() {
        var zoom = FocusZoom()
        let finger = CGPoint(x: 600, y: 150)
        zoom.toggleSmart(at: finger, in: box, maxZoom: 4)
        XCTAssertEqual(zoom.zoom, FocusZoom.smartZoom, accuracy: 0.0001)
        let viewed = zoom.contentFraction(at: finger, in: box)
        XCTAssertEqual(viewed.x, 600 / 800, accuracy: 0.02)
        zoom.toggleSmart(at: finger, in: box, maxZoom: 4)
        XCTAssertEqual(zoom.zoom, FocusZoom.fit, accuracy: 0.0001)
        XCTAssertEqual(zoom.pan, .zero)
    }

    func testSwipePagesOnlyAtFit() {
        XCTAssertEqual(FocusZoom.page(dx: -80, dy: 10, zoom: 1), 1)
        XCTAssertEqual(FocusZoom.page(dx: 80, dy: 4, zoom: 1), -1)
        XCTAssertNil(FocusZoom.page(dx: -80, dy: 10, zoom: 1.4))
        XCTAssertNil(FocusZoom.page(dx: -20, dy: 0, zoom: 1))
        XCTAssertNil(FocusZoom.page(dx: 40, dy: 90, zoom: 1))
    }

    func testRepeatedPinchHoldsTheSamePoint() {
        var zoom = FocusZoom()
        let finger = CGPoint(x: 220, y: 410)
        let before = zoom.contentFraction(at: finger, in: box)
        for delta in [0.15, 0.08, -0.05, 0.22, -0.1, 0.04] {
            zoom.magnify(by: delta, at: finger, in: box, maxZoom: 5, rubber: false)
            let after = zoom.contentFraction(at: finger, in: box)
            XCTAssertEqual(after.x, before.x, accuracy: 0.0001, "delta \(delta)")
            XCTAssertEqual(after.y, before.y, accuracy: 0.0001, "delta \(delta)")
            XCTAssertTrue(zoom.zoom.isFinite)
            XCTAssertTrue(zoom.pan.width.isFinite && zoom.pan.height.isFinite)
        }
        XCTAssertGreaterThan(zoom.zoom, 1)
    }

    func testPanAtFitDoesNothing() {
        var zoom = FocusZoom()
        zoom.pan(by: CGSize(width: 40, height: -30), in: box, rubber: true)
        XCTAssertEqual(zoom.zoom, FocusZoom.fit, accuracy: 0.0001)
        XCTAssertEqual(zoom.pan, .zero)
    }

    func testSmartZoomStopsAtALowCeiling() {
        var zoom = FocusZoom()
        let finger = CGPoint(x: 100, y: 80)
        let before = zoom.contentFraction(at: finger, in: box)
        zoom.toggleSmart(at: finger, in: box, maxZoom: 1.25)
        XCTAssertEqual(zoom.zoom, 1.25, accuracy: 0.0001)
        XCTAssertEqual(zoom.contentFraction(at: finger, in: box).x, before.x, accuracy: 0.0001)
    }

    func testRebaseIgnoresATinyExtentChange() {
        var zoom = FocusZoom()
        zoom.magnify(by: 0.5, at: CGPoint(x: 400, y: 300), in: box, maxZoom: 4, rubber: false)
        let scale = zoom.zoom
        zoom.rebase(from: CGSize(width: 1000, height: 800), to: CGSize(width: 1004, height: 803))
        XCTAssertEqual(zoom.zoom, scale, accuracy: 0.0001)
    }

    func testFitIsAlreadyOneToOneWhenTheSensorIsSmallerThanTheScreen() {
        let maxZoom = FocusZoom.maximum(
            sensor: CGSize(width: 400, height: 300),
            box: box,
            backingScale: 2
        )
        XCTAssertEqual(maxZoom, FocusZoom.fit, accuracy: 0.0001)
    }

    func testOneToOneUsesTheSensorAndTheScreen() {
        let maxZoom = FocusZoom.maximum(
            sensor: CGSize(width: 6000, height: 4000),
            box: box,
            backingScale: 2
        )
        XCTAssertEqual(maxZoom, 4000 / (600 * 2), accuracy: 0.0001)
    }
}
