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
    // MARK: Sky

    /// A synthetic photo: three colour planes and where the sky truly is.
    private struct Scene { var r, g, b, truth: M.Plane }

    /// A deterministic 0 … 1 stream (an LCG), so the scenes are the same on every run.
    private struct LCG {
        var s: UInt64
        mutating func next() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float(s >> 40) / Float(1 << 24) }
    }

    /// Texture as ground has it: per-pixel noise on 4 px blocks of noise, 0 … 1.
    private func ground(_ w: Int, _ h: Int, _ rnd: inout LCG) -> [Float] {
        let bw = w / 4 + 1
        var blocks = [Float](repeating: 0, count: bw * (h / 4 + 1))
        for i in blocks.indices { blocks[i] = rnd.next() }
        var out = [Float](repeating: 0, count: w * h)
        for i in out.indices {
            let block: Float = blocks[(i / w / 4) * bw + (i % w) / 4]
            out[i] = 0.6 * block + 0.4 * rnd.next()
        }
        return out
    }

    /// `sky(t)` (t = 0 at the top, 1 at the bottom) above a jagged skyline (a random walk with
    /// steps, between 35 % and 65 % of the height, or at `line` when given), textured
    /// green-brown ground below, a little noise on everything.
    private func landscape(_ w: Int = 192, _ h: Int = 128, seed: UInt64 = 1, line: Int? = nil,
                           sky: (Float) -> (Float, Float, Float),
                           earth: (Float) -> (Float, Float, Float) = { k in (0.18 + 0.45 * k, 0.30 + 0.40 * k, 0.10 + 0.25 * k) }) -> Scene {
        var rnd = LCG(s: seed)
        var edge = [Int](repeating: 0, count: w), v = Float(h) / 2
        for x in 0..<w {
            v += (rnd.next() - 0.5) * Float(h) / 30
            if x % 16 == 0 { v += (rnd.next() - 0.5) * Float(h) / 5 }
            v = min(0.65 * Float(h), max(0.35 * Float(h), v)); edge[x] = line ?? Int(v)
        }
        let tex = ground(w, h, &rnd)
        var s = Scene(r: M.Plane(width: w, height: h), g: M.Plane(width: w, height: h), b: M.Plane(width: w, height: h), truth: M.Plane(width: w, height: h))
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x, n = (rnd.next() - 0.5) * 0.02
            let c = y < edge[x] ? sky(Float(y) / Float(h)) : earth(tex[i])
            s.r.values[i] = min(1, max(0, c.0 + n)); s.g.values[i] = min(1, max(0, c.1 + n)); s.b.values[i] = min(1, max(0, c.2 + n))
            s.truth.values[i] = y < edge[x] ? 1 : 0
        } }
        return s
    }

    private let blueSky: (Float) -> (Float, Float, Float) = { t in (0.25 + 0.35 * t, 0.45 + 0.30 * t, 0.85 + 0.08 * t) }

    private func sky(_ s: Scene) -> M.Plane? { M.sky(red: s.r, green: s.g, blue: s.b) }

    func testTheGateIsASkyLabelOverTheThreshold() {
        XCTAssertEqual(M.skyScore(["outdoor": 0.9, "sky": 0.6, "blue_sky": 0.7]) ?? 0, 0.7, accuracy: 1e-6, "the most confident sky label")
        XCTAssertNil(M.skyScore(["outdoor": 0.9, "sky": M.skyThreshold - 0.01]), "under the threshold")
        XCTAssertNil(M.skyScore(["kitchen": 0.95, "food": 0.8]), "no sky label")
        XCTAssertNil(M.skyScore([:]))
        XCTAssertEqual(M.skyScore(["horizon": 0.5], among: ["horizon"], threshold: 0.4) ?? 0, 0.5, accuracy: 1e-6, "labels and threshold are parameters")
        XCTAssertTrue(M.skyLabels.contains("sky"))
    }

    func testABlueSkyOverAJaggedSkylineIsFound() throws {
        let s = landscape(sky: blueSky)
        let m = try XCTUnwrap(sky(s))
        XCTAssertGreaterThan(M.iou(m, s.truth), 0.95, "IoU \(M.iou(m, s.truth))")
        XCTAssertTrue(m.values.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(M.sky(red: s.r, green: s.g, blue: s.b), m, "deterministic")
    }

    func testAnOvercastWhiteSkyIsFound() throws {
        let s = landscape(seed: 2, sky: { t in (0.78 + 0.08 * t, 0.80 + 0.08 * t, 0.83 + 0.07 * t) },
                          earth: { k in (0.25 + 0.35 * k, 0.30 + 0.35 * k, 0.25 + 0.25 * k) })
        let m = try XCTUnwrap(sky(s))
        XCTAssertGreaterThan(M.iou(m, s.truth), 0.95, "IoU \(M.iou(m, s.truth))")
    }

    func testASunsetFromPurpleToOrangeIsFound() throws {
        let s = landscape(seed: 3, sky: { t in let k = min(1, t / 0.6); return (0.45 + 0.55 * k, 0.35 + 0.30 * k, 0.65 - 0.35 * k) },
                          earth: { k in (0.06 + 0.25 * k, 0.05 + 0.18 * k, 0.05 + 0.12 * k) })
        let m = try XCTUnwrap(sky(s))
        XCTAssertGreaterThan(M.iou(m, s.truth), 0.95, "IoU \(M.iou(m, s.truth))")
    }

    func testATexturedRoomHasNoSky() {
        var rnd = LCG(s: 4)
        let w = 192, h = 128, tex = ground(w, h, &rnd)
        let r = M.Plane(width: w, height: h, values: tex.map { 0.35 + 0.4 * $0 })!
        let g = M.Plane(width: w, height: h, values: tex.map { 0.25 + 0.3 * $0 })!
        let b = M.Plane(width: w, height: h, values: tex.map { 0.18 + 0.2 * $0 })!
        XCTAssertNil(M.sky(red: r, green: g, blue: b))
        let grey = M.Plane(width: w, height: h, fill: 0.5)
        XCTAssertNil(M.sky(red: grey, green: grey, blue: grey), "a flat mid grey is too dark for overcast")
    }

    func testABlueObjectBelowTheHorizonIsNotSky() throws {
        var s = landscape(seed: 5, sky: blueSky)
        var object = M.Plane(width: s.r.width, height: s.r.height)
        for y in 0..<s.r.height { for x in 0..<s.r.width {
            let dx = Double(x) - 60, dy = Double(y) - 108
            if dx * dx + dy * dy < 14 * 14 { s.r[x, y] = 0.30; s.g[x, y] = 0.55; s.b[x, y] = 0.90; object[x, y] = 1; s.truth[x, y] = 0 }
        } }
        let m = try XCTUnwrap(sky(s))
        XCTAssertLessThan(M.mean(m, inside: object), 0.02, "the blue disc is not sky")
        XCTAssertGreaterThan(M.iou(m, s.truth), 0.95, "IoU \(M.iou(m, s.truth))")
    }

    func testASkyUnderThreePercentIsNil() {
        let s = landscape(seed: 6, line: 3, sky: blueSky)
        XCTAssertLessThan(M.area(s.truth), 0.03)
        XCTAssertNil(sky(s))
    }

    func testSkyIsListedAfterObjectsAndTheBackgroundStaysWhole() throws {
        let s = landscape(seed: 7, sky: blueSky)
        let skyMask = try XCTUnwrap(sky(s))
        let rock = disc(192, 128, cx: 50, cy: 105, r: 22)
        let found = M.name(people: [], objects: [region(rock)], sky: region(skyMask, score: 0.8))
        XCTAssertEqual(found.map(\.id), ["subject", "object-1", "sky", "background"])
        XCTAssertEqual(found.map(\.kind), [.subject, .object, .sky, .background])
        XCTAssertEqual(found[2].score, 0.8, accuracy: 1e-9)
        XCTAssertEqual(found[3].area, 1 - M.area(rock), accuracy: 1e-9, "the background is everything not an object or person, sky included")
        XCTAssertEqual(found[2].dictionary["kind"] as? String, "sky")
        XCTAssertFalse(found[2].outline.isEmpty)
        XCTAssertEqual(M.name(people: [], objects: [], sky: region(skyMask)).map(\.id), ["sky"],
                       "a landscape with nothing in it: the sky alone (the background would be the whole photo)")
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
