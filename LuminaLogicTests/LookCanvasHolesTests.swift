import AppKit
import CoreImage
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

    func testCropGridCutsOnlyItsFourHairlines() {
        let grid = [CGRect(x: 132, y: 0, width: 2, height: 300), CGRect(x: 266, y: 0, width: 2, height: 300),
                    CGRect(x: 0, y: 99, width: 400, height: 2), CGRect(x: 0, y: 199, width: 400, height: 2)]
        for flipped in [false, true] {
            let p = H.maskPath(grid, size: size, flipped: flipped)
            for x in [66.0, 200.0, 333.0] {
                for y in [50.0, 150.0, 250.0] {
                    XCTAssertTrue(drawn(p, x, y, flipped: flipped), "cell (\(x), \(y)) flipped \(flipped)")
                }
            }
            for x in [133.0, 267.0] { XCTAssertFalse(drawn(p, x, 150, flipped: flipped), "vertical \(x) flipped \(flipped)") }
            for y in [100.0, 200.0] { XCTAssertFalse(drawn(p, 200, y, flipped: flipped), "horizontal \(y) flipped \(flipped)") }
        }
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

    func testCropGuidesKeepTheDottedAxisApartFromTheGrid() {
        let raw: [Any] = [
            ["k": "grid", "x0": 10.0, "y0": 20.0, "x1": 30.0, "y1": 20.0],
            ["k": "level", "x0": 0.0, "y0": 40.0, "x1": 100.0, "y1": 40.0],
            ["k": "axis", "x0": 0.0, "y0": 0.0, "x1": 50.0, "y1": 50.0],
            ["k": "grid", "x0": 1.0, "y0": 1.0, "x1": 2.0, "y1": 9_999_999.0],
            ["x0": 1.0, "y0": 1.0, "x1": 2.0, "y1": 2.0],
        ]
        let g = LookCanvasController.Guide.parse(raw)
        XCTAssertEqual(g.map(\.kind), [.grid, .level, .axis, .grid])
        XCTAssertEqual(g[2].a, CGPoint(x: 0, y: 0))
        XCTAssertEqual(g[2].b, CGPoint(x: 50, y: 50))
        XCTAssertEqual(LookCanvasController.Guide.parse(nil), [])
        XCTAssertEqual(LookCanvasController.Guide.parse((0..<30).map { ["k": "axis", "x0": Double($0), "y0": 0.0, "x1": 1.0, "y1": 1.0] }).count, 24)
    }

    /// A straighten used to crop the turned picture back to the upright photo, so the corners that
    /// swung out became a hexagon. They stay, dimmed outside the crop frame; the empty corners of
    /// the bounding box stay clear, and anything past the canvas is dropped.
    @MainActor
    func testStraightenKeepsTheOverhangOutsideTheUprightPhoto() throws {
        let photo = CGRect(x: 40, y: 36, width: 120, height: 80)
        let canvas = CGSize(width: 200, height: 152)
        let src = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: photo)
        let placed = LookCanvasController.draftPlaced(src, photo: photo, canvas: canvas, angle: 25, cover: 1, frame: photo)
        XCTAssertGreaterThan(placed.extent.width, photo.width + 4, "the turned picture is wider than the upright box")
        XCTAssertGreaterThan(placed.extent.height, photo.height + 4, "the turned picture is taller than the upright box")
        XCTAssertFalse(photo.contains(placed.extent))
        XCTAssertTrue(CGRect(origin: .zero, size: canvas).contains(placed.extent))

        let ctx = CIContext(options: [.cacheIntermediates: false])
        func px(_ x: CGFloat, _ y: CGFloat, of image: CIImage) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            var bytes = [UInt8](repeating: 0, count: 4)
            ctx.render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: floor(x), y: floor(y), width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return (bytes[0], bytes[1], bytes[2], bytes[3])
        }

        let mid = px(photo.midX, photo.midY, of: placed)
        XCTAssertGreaterThan(mid.r, 250, "inside the crop frame the picture is undimmed")
        XCTAssertGreaterThan(mid.a, 250)

        // The left side of the turned rectangle crosses the centre line outside the upright box.
        var overhang: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)?
        var x = photo.minX - 1
        while x > placed.extent.minX + 1 {
            let s = px(x, photo.midY, of: placed)
            if s.a > 200 { overhang = s; break }
            x -= 1
        }
        let over = try XCTUnwrap(overhang, "a corner that left the upright box is still drawn")
        XCTAssertLessThan(over.r, 180, "outside the crop frame that overhang is veiled")
        XCTAssertGreaterThan(over.a, 200)

        let wedge = px(placed.extent.minX + 1.5, placed.extent.minY + 1.5, of: placed)
        XCTAssertLessThan(wedge.a, 16, "the bounding box's empty corner is not painted")

        // Cover scale sticks out of the upright box too; the same crop used to cut it off.
        let scaled = LookCanvasController.draftPlaced(src, photo: photo, canvas: canvas, angle: 0, cover: 1.2, frame: photo)
        XCTAssertGreaterThan(scaled.extent.width, photo.width + 4)
        XCTAssertGreaterThan(px(photo.minX - 4, photo.midY, of: scaled).a, 200)
        XCTAssertLessThan(px(photo.minX - 4, photo.midY, of: scaled).r, 180)

        // No turn: the upright photo is unchanged, and an inset frame still dims its margin.
        let still = LookCanvasController.draftPlaced(src, photo: photo, canvas: canvas, angle: 0, cover: 1, frame: photo.insetBy(dx: 16, dy: 12))
        XCTAssertEqual(still.extent.width, photo.width, accuracy: 1)
        XCTAssertEqual(still.extent.height, photo.height, accuracy: 1)
        XCTAssertGreaterThan(px(photo.midX, photo.midY, of: still).r, 250)
        XCTAssertLessThan(px(photo.minX + 4, photo.midY, of: still).r, 180)
        XCTAssertGreaterThan(px(photo.minX + 4, photo.midY, of: still).a, 200)
    }
}
