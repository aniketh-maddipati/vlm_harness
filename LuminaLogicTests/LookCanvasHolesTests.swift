import AppKit
import XCTest
@testable import Lumina

/// The page's chrome over the Edit canvas (`canvasLayout`'s `holes`): read without trusting it,
/// turned into a layer mask that leaves those rects see-through, and never a reason to rebuild a
/// base or render the look again.
final class LookCanvasHolesTests: XCTestCase {
    typealias H = LookCanvasHoles
    let rect = CGRect(x: 100, y: 50, width: 400, height: 300)

    private func hole(_ x: Any, _ y: Any, _ w: Any, _ h: Any) -> [String: Any] { ["x": x, "y": y, "w": w, "h": h] }

    // MARK: Parsing

    func testHolesAreInTheCanvasFrameTopLeft() {
        XCTAssertEqual(H.parse([hole(110, 60, 40, 20), hole(460, 320, 40, 30)], in: rect),
                       [CGRect(x: 10, y: 10, width: 40, height: 20), CGRect(x: 360, y: 270, width: 40, height: 30)])
    }

    func testHolesAreClippedToTheCanvasAndOutsideOnesDropped() {
        let got = H.parse([hole(80, 40, 40, 20),         // over the top-left corner
                           hole(480, 330, 100, 100),     // over the bottom-right corner
                           hole(0, 0, 50, 50),           // wholly outside
                           hole(500, 50, 10, 10),        // touching the right edge only
                           hole(0, 0, 2000, 2000)], in: rect) // covers everything
        XCTAssertEqual(got, [CGRect(x: 0, y: 0, width: 20, height: 10), CGRect(x: 380, y: 280, width: 20, height: 20),
                             CGRect(x: 0, y: 0, width: 400, height: 300)])
    }

    func testAtMostSixteenAreRead() {
        let many = (0..<20).map { hole(100 + $0 * 10, 50, 5, 5) }
        let got = H.parse(many, in: rect)
        XCTAssertEqual(got.count, H.maxCount)
        XCTAssertEqual(got.last, CGRect(x: 150, y: 0, width: 5, height: 5))
        // Garbage among the first sixteen still counts toward them: the read is bounded, not the result.
        XCTAssertEqual(H.parse(Array(repeating: "x", count: 16) + [hole(110, 60, 5, 5)], in: rect), [])
    }

    func testGarbageIsDroppedNeverACrash() {
        let bad: [Any] = [
            "hole", 42, NSNull(), [1, 2, 3, 4], [:] as [String: Any],
            hole(Double.nan, 60, 10, 10), hole(110, Double.infinity, 10, 10), hole(110, 60, -Double.infinity, 10), hole(110, 60, 10, 1e308),
            hole(1e300, 60, 10, 10), hole("110", 60, 10, 10), hole(true, 60, 10, 10), hole(110, 60, 0, 10), hole(110, 60, 10, -5),
            ["x": 110, "y": 60, "w": 10] as [String: Any], hole(110, 60, Int.max, Int.max),
        ]
        for b in bad { XCTAssertEqual(H.parse([b], in: rect), [], "\(b)") }
        for v in ["holes", 42, NSNull(), ["x": 1] as [String: Any]] as [Any] { XCTAssertEqual(H.parse(v, in: rect), [], "\(v)") }
        XCTAssertEqual(H.parse(nil, in: rect), [])
        // A canvas that is not a rect has no holes.
        for r in [CGRect.null, .infinite, .zero, CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10)] {
            XCTAssertEqual(H.parse([hole(0, 0, 10, 10)], in: r), [], "\(r)")
        }
        // Fractions survive; the mask is in points.
        XCTAssertEqual(H.parse([hole(110.5, 60.25, 10, 10)], in: rect), [CGRect(x: 10.5, y: 10.25, width: 10, height: 10)])
    }

    // MARK: Mask geometry

    private let size = CGSize(width: 400, height: 300)

    /// Is the canvas drawn at this point of the canvas frame (top-left origin)?
    private func drawn(_ path: CGPath?, _ x: CGFloat, _ y: CGFloat, flipped: Bool = false) -> Bool {
        guard let path else { return true }
        return path.contains(CGPoint(x: x, y: flipped ? y : size.height - y))
    }

    func testNoHolesNoMask() {
        XCTAssertNil(H.maskPath([], size: size, flipped: false))
        XCTAssertNil(H.maskPath([], size: size, flipped: true))
    }

    func testAHoleAtEachCornerIsSeeThroughAndTheRestDrawn() {
        let corners = [CGRect(x: 0, y: 0, width: 40, height: 20), CGRect(x: 360, y: 0, width: 40, height: 20),
                       CGRect(x: 0, y: 280, width: 40, height: 20), CGRect(x: 360, y: 280, width: 40, height: 20)]
        for flipped in [false, true] {
            let p = H.maskPath(corners, size: size, flipped: flipped)
            for c in corners { XCTAssertFalse(drawn(p, c.midX, c.midY, flipped: flipped), "\(c) flipped \(flipped)") }
            for (x, y) in [(200.0, 150.0), (50.0, 10.0), (20.0, 30.0), (350.0, 290.0), (380.0, 270.0)] {
                XCTAssertTrue(drawn(p, x, y, flipped: flipped), "(\(x), \(y)) flipped \(flipped)")
            }
        }
    }

    func testTopIsTopInAnUnflippedLayer() {
        // A pill at the canvas's top edge (page frame) is cut at the layer's top: high y, bottom-left origin.
        let p = H.maskPath([CGRect(x: 0, y: 0, width: 400, height: 20)], size: size, flipped: false)!
        XCTAssertFalse(p.contains(CGPoint(x: 200, y: 290)))
        XCTAssertTrue(p.contains(CGPoint(x: 200, y: 10)))
    }

    func testOverlappingHolesAreOneHole() {
        let a = CGRect(x: 100, y: 100, width: 100, height: 60), b = CGRect(x: 150, y: 130, width: 100, height: 60)
        let p = H.maskPath([a, b], size: size, flipped: false)
        for (x, y) in [(120.0, 110.0), (175.0, 145.0), (240.0, 180.0)] { XCTAssertFalse(drawn(p, x, y), "(\(x), \(y))") }
        XCTAssertTrue(drawn(p, 240, 110))
        XCTAssertTrue(drawn(p, 120, 180))
        // The same hole twice is still a hole.
        XCTAssertFalse(drawn(H.maskPath([a, a], size: size, flipped: false), 150, 130))
    }

    func testAHoleOverTheWholeCanvasLeavesNothingDrawn() {
        let p = H.maskPath([CGRect(origin: .zero, size: size)], size: size, flipped: false)
        for (x, y) in [(1.0, 1.0), (200.0, 150.0), (399.0, 299.0)] { XCTAssertFalse(drawn(p, x, y), "(\(x), \(y))") }
    }

    // MARK: On the canvas

    /// Through the controller, as the bridge calls it: holes become the view's layer mask; holes
    /// alone move nothing else (frame, drawable, renders); the same layout again is a no-op; no
    /// holes, no mask. Without a Metal device (a CI runner) the controller is on the image path
    /// and only survival is checked.
    @MainActor
    func testHolesMaskTheCanvasAndNothingElse() throws {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let canvas = LookCanvasController(pipeline: try LookPipeline(rules: LookRules.bundled()), host: host)
        let pill = [CGRect(x: 10, y: 10, width: 60, height: 20)]
        canvas.layout(rect: rect, visible: true, dpr: 2, holes: pill)
        guard canvas.path == .native else {
            canvas.layout(rect: rect, visible: true, dpr: 2, holes: [])
            return
        }
        let view = try XCTUnwrap(host.subviews.first)
        let layer = try XCTUnwrap(view.layer)
        XCTAssertEqual(view.frame, NSRect(x: 100, y: 250, width: 400, height: 300))
        let mask = try XCTUnwrap(layer.mask as? CAShapeLayer)
        XCTAssertEqual(mask.frame, CGRect(x: 0, y: 0, width: 400, height: 300))
        let p = try XCTUnwrap(mask.path)
        XCTAssertFalse(p.contains(CGPoint(x: 40, y: 300 - 20)), "the pill is see-through")
        XCTAssertTrue(p.contains(CGPoint(x: 200, y: 150)), "the photo is drawn")
        XCTAssertEqual(canvas.snapshot()["holes"] as? Int, 1)

        let drawable = (view as? LookCanvasView)?.drawableSize
        let renders = canvas.snapshot()["renders"] as? Int
        // Holes only: a new mask, the same frame and drawable, no render.
        let two = pill + [CGRect(x: 330, y: 270, width: 60, height: 20)]
        canvas.layout(rect: rect, visible: true, dpr: 2, holes: two)
        XCTAssertEqual(view.frame, NSRect(x: 100, y: 250, width: 400, height: 300))
        XCTAssertEqual((view as? LookCanvasView)?.drawableSize, drawable)
        XCTAssertEqual(canvas.snapshot()["renders"] as? Int, renders)
        XCTAssertEqual(canvas.snapshot()["holes"] as? Int, 2)
        let mask2 = try XCTUnwrap(layer.mask as? CAShapeLayer)
        XCTAssertTrue(mask2 === mask, "the mask layer is reused")
        XCTAssertFalse(try XCTUnwrap(mask2.path).contains(CGPoint(x: 360, y: 300 - 280)))

        // The same layout again: nothing changes, the mask path is the same object.
        let same = mask2.path
        canvas.layout(rect: rect, visible: true, dpr: 2, holes: two)
        XCTAssertTrue((layer.mask as? CAShapeLayer)?.path === same)

        // A new rect re-cuts the mask for the new size.
        canvas.layout(rect: CGRect(x: 100, y: 50, width: 200, height: 100), visible: true, dpr: 2, holes: pill)
        XCTAssertEqual((layer.mask as? CAShapeLayer)?.frame, CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertFalse(try XCTUnwrap((layer.mask as? CAShapeLayer)?.path).contains(CGPoint(x: 40, y: 100 - 20)))

        // No holes: no mask.
        canvas.layout(rect: rect, visible: true, dpr: 2, holes: [])
        XCTAssertNil(layer.mask)
        XCTAssertEqual(canvas.snapshot()["holes"] as? Int, 0)

        // A hostile rect hides the canvas; the next real layout places it (and its holes) again.
        canvas.layout(rect: .infinite, visible: true, dpr: 2, holes: pill)
        XCTAssertTrue(view.isHidden)
        canvas.layout(rect: rect, visible: true, dpr: 2, holes: pill)
        XCTAssertFalse(view.isHidden)
        XCTAssertNotNil(layer.mask)
    }

    // MARK: Under a title bar

    /// On macOS 26 the web view fills the host but keeps the strip under the title bar out of the
    /// page, so the page's CSS y = 0 is that far below the host's top. The rect is placed up from the
    /// viewport's bottom (the host's): a 900 pt host whose page is 868 pt tall puts a rect at CSS
    /// y = 60 at 32 pt + 60 pt below the host's top, not 60 pt (the photo over the tab bar).
    func testTheCanvasIsPlacedFromThePageViewportNotTheHostTop() {
        let rect = CGRect(x: 20, y: 60, width: 1000, height: 600)
        XCTAssertEqual(LookCanvasController.frame(for: rect, hostHeight: 900, viewportHeight: 868), NSRect(x: 20, y: 208, width: 1000, height: 600))
        // No viewport height, or one the host can't hold: the viewport is the whole host, as before.
        for vh: CGFloat? in [nil, 0, -5, 901, CGFloat.nan, CGFloat.infinity] {
            XCTAssertEqual(LookCanvasController.frame(for: rect, hostHeight: 900, viewportHeight: vh), NSRect(x: 20, y: 240, width: 1000, height: 600), "\(String(describing: vh))")
        }
    }

    @MainActor
    func testTheViewSitsWhereThePageViewportPutsTheRect() throws {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let canvas = LookCanvasController(pipeline: try LookPipeline(rules: LookRules.bundled()), host: host)
        canvas.layout(rect: rect, visible: true, dpr: 2, viewportHeight: 568)
        guard canvas.path == .native else { return }
        let view = try XCTUnwrap(host.subviews.first)
        XCTAssertEqual(view.frame, NSRect(x: 100, y: 218, width: 400, height: 300))
        // The window's title bar goes away (full screen): the same rect moves with the viewport.
        canvas.layout(rect: rect, visible: true, dpr: 2, viewportHeight: 600)
        XCTAssertEqual(view.frame, NSRect(x: 100, y: 250, width: 400, height: 300))
    }
}
