import XCTest
@testable import Lumina

/// Edit's automatic masks (DESIGN-ASKS Prompt 28) without Vision: the algebra, the edge
/// refinement, the outline the page draws and which mask is which, on synthetic planes.
/// Foundation only: these also run in the Linux Swift sandbox.
final class LookMasksTests: XCTestCase {
    typealias M = LookMasks

    private func plane(_ w: Int, _ h: Int, _ f: (Int, Int) -> Float) -> M.Plane {
        var p = M.Plane(width: w, height: h)
        for y in 0..<h { for x in 0..<w { p[x, y] = f(x, y) } }
        return p
    }

    private func disc(_ w: Int, _ h: Int, cx: Double, cy: Double, r: Double) -> M.Plane {
        plane(w, h) { x, y in
            let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
            return dx * dx + dy * dy < r * r ? 1 : 0
        }
    }

    private func region(_ p: M.Plane, score: Double = 0.9, saliency: Double? = nil) -> M.Region {
        M.Region(mask: p, score: score, saliency: saliency)
    }

    // MARK: Algebra and measures

    func testAlgebraFollowsTheSubMaskModes() {
        let a = plane(4, 1) { x, _ in [1, 1, 0, 0.5][x] }
        let b = plane(4, 1) { x, _ in [1, 0, 1, 0.5][x] }
        XCTAssertEqual(M.union(a, b).values, [1, 1, 1, 0.5])
        XCTAssertEqual(M.intersect(a, b).values, [1, 0, 0, 0.5])
        XCTAssertEqual(M.subtract(a, b).values, [0, 1, 0, 0.25])
        XCTAssertEqual(M.invert(a).values, [0, 0, 1, 0.5])
    }

    func testAreaBoxAndIoU() {
        let p = plane(10, 10) { x, y in (2...5).contains(x) && (4...8).contains(y) ? 1 : 0 }
        XCTAssertEqual(M.area(p), 0.2, accuracy: 1e-9)
        let b = try! XCTUnwrap(M.box(p))
        XCTAssertEqual(b.x, 0.2, accuracy: 1e-9); XCTAssertEqual(b.y, 0.4, accuracy: 1e-9)
        XCTAssertEqual(b.w, 0.4, accuracy: 1e-9); XCTAssertEqual(b.h, 0.5, accuracy: 1e-9)
        XCTAssertNil(M.box(M.Plane(width: 10, height: 10)), "nothing selected, no box")
        XCTAssertEqual(M.iou(p, p), 1)
        XCTAssertEqual(M.iou(p, M.invert(p)), 0)
        XCTAssertEqual(M.iou(M.Plane(width: 3, height: 3), M.Plane(width: 3, height: 3)), 0, "two empty masks")
    }

    // MARK: Resampling and the guided filter

    func testResizeToOwnSizeIsUnchangedAndAFlatPlaneStaysFlat() {
        let p = disc(32, 24, cx: 16, cy: 12, r: 8)
        XCTAssertEqual(M.resized(p, width: 32, height: 24), p)
        let flat = M.resized(M.Plane(width: 7, height: 5, fill: 0.25), width: 31, height: 17)
        XCTAssertTrue(flat.values.allSatisfy { abs($0 - 0.25) < 1e-6 })
        let up = M.resized(p, width: 64, height: 48)
        XCTAssertEqual(M.area(up), M.area(p), accuracy: 0.02, "upsampling keeps the selected share")
    }

    func testBoxMeanKeepsAFlatPlaneFlatToTheEdges() {
        let flat = M.boxMean(M.Plane(width: 9, height: 6, fill: 0.7), radius: 3)
        XCTAssertTrue(flat.values.allSatisfy { abs($0 - 0.7) < 1e-5 }, "the window is cut at the edges, not padded with 0")
        let impulse = plane(5, 5) { x, y in x == 2 && y == 2 ? 9 : 0 }
        XCTAssertEqual(M.boxMean(impulse, radius: 1)[2, 2], 1, accuracy: 1e-6)
        XCTAssertEqual(M.boxMean(impulse, radius: 1)[0, 0], 0, accuracy: 1e-6)
    }

    /// A coarse mask (a square too big by 4 px on each side) over a photo whose own edge is the
    /// smaller square: the guided filter moves the mask's boundary onto the photo's edge.
    func testGuidedFilterSnapsACoarseMaskToThePhotosEdge() {
        let w = 64, h = 64
        let photo = plane(w, h) { x, y in (20..<44).contains(x) && (20..<44).contains(y) ? 0.9 : 0.1 }
        let truth = plane(w, h) { x, y in (20..<44).contains(x) && (20..<44).contains(y) ? 1 : 0 }
        let coarse = M.resized(M.resized(plane(w, h) { x, y in (16..<48).contains(x) && (16..<48).contains(y) ? 1 : 0 }, width: 8, height: 8), width: w, height: h)
        let refined = M.guided(coarse, guide: photo, radius: 8, eps: 1e-3)
        XCTAssertGreaterThan(M.iou(refined, truth), M.iou(coarse, truth) + 0.1, "refined \(M.iou(refined, truth)) vs coarse \(M.iou(coarse, truth))")
        XCTAssertTrue(refined.values.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(M.guided(M.Plane(width: 9, height: 9, fill: 1), guide: photo.cropForTest(9, 9), radius: 2).values.min()!, 1, accuracy: 1e-3,
                       "a full mask stays full")
    }

    // MARK: Outlines

    func testOutlineOfADiscIsOneLoopWithItsArea() {
        let w = 80, h = 60
        let p = disc(w, h, cx: 40, cy: 30, r: 20)
        let loops = M.outline(p)
        XCTAssertEqual(loops.count, 1)
        let loop = loops[0]
        XCTAssertLessThan(loop.count, 40, "simplified: \(loop.count) points")
        XCTAssertEqual(abs(shoelace(loop)) * Double(w * h), Double.pi * 400, accuracy: Double.pi * 400 * 0.03)
        XCTAssertTrue(loop.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }, "fractions of the photo")
        XCTAssertGreaterThan(shoelace(loop), 0, "the outer edge runs clockwise on screen")
    }

    func testOutlineOfASquareIsItsFourCorners() {
        let p = plane(40, 40) { x, y in (10..<30).contains(x) && (10..<30).contains(y) ? 1 : 0 }
        let loop = try! XCTUnwrap(M.outline(p).first)
        XCTAssertEqual(Set(loop.map { "\($0.x),\($0.y)" }), ["0.25,0.25", "0.75,0.25", "0.75,0.75", "0.25,0.75"])
    }

    func testARingHasAHoleRunningTheOtherWay() {
        let w = 60, h = 60
        let p = M.subtract(disc(w, h, cx: 30, cy: 30, r: 20), disc(w, h, cx: 30, cy: 30, r: 10))
        let loops = M.outline(p)
        XCTAssertEqual(loops.count, 2)
        XCTAssertGreaterThan(shoelace(loops[0]), 0); XCTAssertLessThan(shoelace(loops[1]), 0, "the hole runs the other way: even-odd fill")
    }

    func testDiagonalNeighboursAreSeparateLoopsAndSpecksAreDropped() {
        var p = plane(20, 20) { x, y in ((2..<8).contains(x) && (2..<8).contains(y)) || ((8..<14).contains(x) && (8..<14).contains(y)) ? 1 : 0 }
        p[18, 1] = 1     // one stray pixel
        let loops = M.outline(p)
        XCTAssertEqual(loops.count, 2, "two squares touching at a corner; the stray pixel is under minArea")
        XCTAssertTrue(M.outline(M.Plane(width: 5, height: 5)).isEmpty)
        XCTAssertEqual(M.outline(p, maxLoops: 1).count, 1)
    }

    private func shoelace(_ loop: [M.Point]) -> Double {
        var a = 0.0
        for i in loop.indices { let p = loop[i], q = loop[(i + 1) % loop.count]; a += p.x * q.y - q.x * p.y }
        return a / 2
    }

    // MARK: Which mask is which

    func testSubjectPeopleObjectsAndBackground() {
        let w = 80, h = 60
        let person = disc(w, h, cx: 25, cy: 30, r: 15)
        let dog = disc(w, h, cx: 62, cy: 40, r: 8)
        let personAgain = disc(w, h, cx: 25, cy: 31, r: 15)   // the foreground finder sees the person too
        let found = M.name(people: [region(person, saliency: 0.6)],
                           objects: [region(personAgain, saliency: 0.6), region(dog, saliency: 0.9)])
        XCTAssertEqual(found.map(\.id), ["subject", "person-1", "object-1", "background"])
        XCTAssertEqual(found.map(\.kind), [.subject, .person, .object, .background])
        XCTAssertEqual(found[0].area, M.area(person), accuracy: 1e-9, "saliency × √area: the person, not the brighter small dog")
        XCTAssertEqual(found[2].area, M.area(dog), accuracy: 1e-9, "the object that is the person is not listed twice")
        XCTAssertEqual(found[3].area, 1 - M.area(M.union(person, dog)), accuracy: 1e-9)
        XCTAssertFalse(found[3].outline.isEmpty)
    }

    func testWithoutSaliencyTheLargestIsTheSubject() {
        let w = 40, h = 40
        let small = disc(w, h, cx: 10, cy: 10, r: 4), large = disc(w, h, cx: 26, cy: 26, r: 10)
        let found = M.name(people: [], objects: [region(small), region(large)])
        XCTAssertEqual(found.first?.area ?? 0, M.area(large), accuracy: 1e-9)
    }

    func testNothingFoundIsAnEmptyListAndTinyOrHugeIsLeftOut() {
        XCTAssertTrue(M.name(people: [], objects: []).isEmpty)
        let speck = plane(100, 100) { x, y in x == 5 && y == 5 ? 1 : 0 }
        XCTAssertTrue(M.name(people: [], objects: [region(speck)]).isEmpty, "under 0.2 % of the photo")
        let all = M.name(people: [], objects: [region(M.Plane(width: 10, height: 10, fill: 1))])
        XCTAssertEqual(all.map(\.kind), [.subject, .object], "no background when the object is the whole photo")
    }

    func testDictionaryIsWhatThePageReads() {
        let found = M.name(people: [], objects: [region(disc(40, 40, cx: 20, cy: 20, r: 10), score: 0.876543)])
        let d = found[0].dictionary
        XCTAssertEqual(d["id"] as? String, "subject"); XCTAssertEqual(d["kind"] as? String, "subject")
        XCTAssertEqual(d["score"] as? Double, 0.8765)
        XCTAssertEqual((d["box"] as? [Double])?.count, 4)
        let outline = try! XCTUnwrap(d["outline"] as? [[[Double]]])
        XCTAssertEqual(outline.count, 1); XCTAssertTrue(outline[0].allSatisfy { $0.count == 2 })
        XCTAssertTrue(JSONSerialization.isValidJSONObject(found.map(\.dictionary)))
    }
}

private extension LookMasks.Plane {
    /// The top-left `w × h` of the plane.
    func cropForTest(_ w: Int, _ h: Int) -> LookMasks.Plane {
        var p = LookMasks.Plane(width: w, height: h)
        for y in 0..<h { for x in 0..<w { p[x, y] = self[x, y] } }
        return p
    }
}

/// Rasterising an outline for the render (adjustments inside a mask, DESIGN-ASKS Prompt 29):
/// the share of each pixel inside, even-odd, row 0 at the photo's top.
extension LookMasksTests {
    private typealias P = LookMasks.Point

    private func mean(_ p: LookMasks.Plane) -> Double { p.values.reduce(0) { $0 + Double($1) } / Double(p.values.count) }

    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [P] {
        [P(x: x0, y: y0), P(x: x1, y: y0), P(x: x1, y: y1), P(x: x0, y: y1)]
    }

    private func circle(_ cx: Double, _ cy: Double, _ r: Double, n: Int = 360, clockwise: Bool = true) -> [P] {
        (0..<n).map { i in
            let a = 2 * Double.pi * Double(clockwise ? i : n - i) / Double(n)
            return P(x: cx + r * cos(a), y: cy + r * sin(a))
        }
    }

    func testRasterOfASquareIsItsArea() {
        let grid = M.raster([rect(0.25, 0.25, 0.75, 0.75)], width: 64, height: 64)
        XCTAssertEqual(mean(grid), 0.25, accuracy: 1e-6, "edges on pixel boundaries: exact")
        XCTAssertEqual(grid[16, 16], 1); XCTAssertEqual(grid[15, 16], 0); XCTAssertEqual(grid[47, 47], 1); XCTAssertEqual(grid[48, 47], 0)
        let off = M.raster([rect(0.13, 0.21, 0.71, 0.67)], width: 100, height: 80)
        XCTAssertEqual(mean(off), 0.58 * 0.46, accuracy: 0.002, "off the grid: within a quarter row on each edge")
    }

    func testRasterAntialiasesAlongARow() {
        // The left edge half way through pixel 10, the right edge a quarter into pixel 30.
        let p = M.raster([rect(10.5 / 40, 0, 30.25 / 40, 1)], width: 40, height: 4)
        for y in 0..<4 {
            XCTAssertEqual(p[9, y], 0); XCTAssertEqual(p[10, y], 0.5, accuracy: 1e-6); XCTAssertEqual(p[11, y], 1)
            XCTAssertEqual(p[29, y], 1); XCTAssertEqual(p[30, y], 0.25, accuracy: 1e-6); XCTAssertEqual(p[31, y], 0)
        }
    }

    func testRasterOfADiscAndARing() {
        let disc = M.raster([circle(0.5, 0.5, 0.3)], width: 200, height: 200)
        XCTAssertEqual(mean(disc), Double.pi * 0.09, accuracy: 0.002)
        XCTAssertEqual(disc[100, 100], 1); XCTAssertEqual(disc[2, 2], 0)
        // A hole is a loop of its own, filled even-odd: either way round it is a hole.
        for clockwise in [true, false] {
            let ring = M.raster([circle(0.5, 0.5, 0.4), circle(0.5, 0.5, 0.2, clockwise: clockwise)], width: 200, height: 200)
            XCTAssertEqual(mean(ring), Double.pi * (0.16 - 0.04), accuracy: 0.003)
            XCTAssertEqual(ring[100, 100], 0, "the hole")
            XCTAssertEqual(ring[100, 40], 1, "the ring, 0.3 above the centre")
        }
        // Two overlapping loops: the overlap is outside (even-odd), as on the page's canvas.
        let two = M.raster([rect(0, 0, 0.6, 1), rect(0.4, 0, 1, 1)], width: 10, height: 2)
        XCTAssertEqual(two.values.prefix(10).map { Int($0.rounded()) }, [1, 1, 1, 1, 0, 0, 1, 1, 1, 1])
    }

    func testRasterRowZeroIsThePhotosTop() {
        let top = M.raster([rect(0, 0, 1, 0.25)], width: 8, height: 8)
        XCTAssertEqual(top[3, 0], 1); XCTAssertEqual(top[3, 1], 1); XCTAssertEqual(top[3, 2], 0); XCTAssertEqual(top[3, 7], 0)
        // The outline of a plane, rasterised again at its own size, is the plane.
        let d = disc(64, 48, cx: 20, cy: 14, r: 9)
        let again = M.raster(M.outline(d, tolerance: 0), width: 64, height: 48)
        XCTAssertEqual(M.iou(d, again), 1, accuracy: 1e-9)
        XCTAssertEqual(M.area(again), M.area(d), accuracy: 1e-9)
    }

    func testRasterFeatherSoftensTheEdgeAndKeepsTheInside() {
        let hard = M.raster([rect(0.25, 0.25, 0.75, 0.75)], width: 128, height: 128)
        let soft = M.raster([rect(0.25, 0.25, 0.75, 0.75)], width: 128, height: 128, feather: 0.06)
        XCTAssertEqual(mean(soft), mean(hard), accuracy: 0.01, "the feather moves no area in or out")
        XCTAssertEqual(soft[64, 64], 1, accuracy: 1e-5); XCTAssertEqual(soft[2, 2], 0, accuracy: 1e-5)
        XCTAssertTrue(soft[32, 64] > 0.2 && soft[32, 64] < 0.8, "the edge is soft: \(soft[32, 64])")
        XCTAssertTrue(soft[30, 64] > 0 && soft[30, 64] < soft[33, 64], "and rises across it")
        // A whole-frame mask stays whole to the edges (the window is cut there, as boxMean's).
        let all = M.raster([rect(0, 0, 1, 1)], width: 32, height: 16, feather: 0.2)
        XCTAssertTrue(all.values.allSatisfy { abs($0 - 1) < 1e-5 })
    }

    func testRasterIgnoresWhatEnclosesNothing() {
        XCTAssertEqual(mean(M.raster([], width: 8, height: 8)), 0)
        XCTAssertEqual(mean(M.raster([[P(x: 0, y: 0), P(x: 1, y: 1)]], width: 8, height: 8)), 0, "two points are no loop")
        XCTAssertEqual(mean(M.raster([[P(x: .nan, y: 0), P(x: 1, y: .infinity), P(x: 0, y: 1)]], width: 8, height: 8)), 0)
        XCTAssertEqual(M.raster([rect(0, 0, 1, 1)], width: 0, height: 5).values.count, 0)
        // Beyond the photo is clipped to it.
        XCTAssertEqual(mean(M.raster([rect(-1, -1, 2, 0.5)], width: 10, height: 10)), 0.5, accuracy: 1e-6)
    }

    func testRasterSizeIsOneOfAFewWithThePhotosAspect() {
        XCTAssertTrue(M.rasterSize(photo: 300, 200) == (512, 341))
        XCTAssertTrue(M.rasterSize(photo: 200, 300) == (341, 512))
        XCTAssertTrue(M.rasterSize(photo: 60, 40) == (256, 171))
        XCTAssertTrue(M.rasterSize(photo: 6000, 4000) == (2048, 1365))
        XCTAssertTrue(M.rasterSize(photo: 6000, 4000, cap: 1024) == (1024, 683))
        XCTAssertTrue(M.rasterSize(photo: 0, 10) == (1, 1))
        XCTAssertTrue(M.rasterSize(photo: .infinity, 10) == (1, 1))
    }
}
