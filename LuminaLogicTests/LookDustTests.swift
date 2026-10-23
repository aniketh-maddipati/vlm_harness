import Foundation
import XCTest
@testable import Lumina

/// Sensor dust: found across a synthetic shoot where the truth is known (spots placed on frames of
/// different scenes), refused where it would be wrong (a locked-off series, too few frames), and
/// lifted out of a photo close to the clean frame. Foundation only, so it runs on Linux too.
final class LookDustTests: XCTestCase {
    private struct Rand {
        var s: UInt64
        mutating func next() -> Double {
            s &+= 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
        mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    }

    private struct Dust { let x: Double; let y: Double; let sigma: Double; let depth: Double }

    /// A scene of linear luma: a gradient (a sky), soft blotches, a few hard-edged blocks and one
    /// textured patch (foliage), with sensor noise. Each seed is a different picture.
    private func scene(_ seed: UInt64, _ w: Int, _ h: Int, noise: Double = 0.003, texture: Bool = true) -> LookDust.Plane {
        var r = Rand(s: seed)
        let a = r.range(0.12, 0.5), gx = r.range(-0.15, 0.15), gy = r.range(-0.2, 0.2)
        // Soft blotches: wide Gaussian bumps, smooth everywhere as a sky or a wall is.
        let bumps = (0..<8).map { _ in (x: r.range(0, Double(w)), y: r.range(0, Double(h)), s: r.range(0.08, 0.3) * Double(w), a: r.range(-0.06, 0.06)) }
        var blocks: [(Int, Int, Int, Int, Double)] = []
        for _ in 0..<3 {
            let bx = Int(r.range(0, Double(w) * 0.8)), by = Int(r.range(0, Double(h) * 0.8))
            blocks.append((bx, by, bx + Int(r.range(20, Double(w) / 4)), by + Int(r.range(20, Double(h) / 4)), r.range(-0.08, 0.15)))
        }
        let tx = Int(r.range(0, Double(w) * 0.6)), ty = Int(r.range(0, Double(h) * 0.6))
        var p = LookDust.Plane(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let u = Double(x) / Double(w), v = Double(y) / Double(h)
                var l = a + gx * u + gy * v
                for b in bumps {
                    let dx = Double(x) - b.x, dy = Double(y) - b.y
                    l += b.a * exp(-(dx * dx + dy * dy) / (2 * b.s * b.s))
                }
                for b in blocks where x >= b.0 && x < b.2 && y >= b.1 && y < b.3 { l += b.4 }
                if texture && x >= tx && x < tx + w / 5 && y >= ty && y < ty + h / 5 { l *= r.range(0.6, 1.4) }
                l += (r.next() - 0.5) * 2 * noise * 1.7
                p[x, y] = Float(min(0.85, max(0.03, l)))
            }
        }
        return p
    }

    private func dusted(_ p: LookDust.Plane, _ dust: [Dust]) -> LookDust.Plane {
        var out = p
        for d in dust {
            let x0 = max(0, Int(d.x - 5 * d.sigma)), x1 = min(p.width - 1, Int(d.x + 5 * d.sigma))
            let y0 = max(0, Int(d.y - 5 * d.sigma)), y1 = min(p.height - 1, Int(d.y + 5 * d.sigma))
            for y in y0...y1 {
                for x in x0...x1 {
                    let dx = Double(x) + 0.5 - d.x, dy = Double(y) + 0.5 - d.y
                    out[x, y] *= Float(1 - d.depth * exp(-(dx * dx + dy * dy) / (2 * d.sigma * d.sigma)))
                }
            }
        }
        return out
    }

    private let w = 640, h = 427
    private let truth = [Dust(x: 120.5, y: 80.5, sigma: 2.0, depth: 0.25), Dust(x: 400.5, y: 300.5, sigma: 3.0, depth: 0.12),
                         Dust(x: 560.5, y: 60.5, sigma: 1.4, depth: 0.3), Dust(x: 250.5, y: 350.5, sigma: 2.5, depth: 0.06),
                         Dust(x: 330.5, y: 150.5, sigma: 4.0, depth: 0.08)]

    func testFindsTheDustAcrossAShoot() {
        let acc = LookDust.Accumulator(width: w, height: h)
        for seed in 1...30 { XCTAssertTrue(acc.add(dusted(scene(UInt64(seed), w, h), truth))) }
        let found = acc.spots()
        for t in truth {
            let match = found.first { s in
                let dx = s.x * Double(w) - t.x, dy = s.y * Double(h) - t.y
                return (dx * dx + dy * dy).squareRoot() < 2
            }
            XCTAssertNotNil(match, "missed the spot at \(t.x), \(t.y): found \(found.map { ($0.x * Double(w), $0.y * Double(h), $0.depth) })")
            if let m = match {
                XCTAssertEqual(m.depth, t.depth, accuracy: t.depth * 0.5 + 0.01, "depth at \(t.x), \(t.y)")
                XCTAssertGreaterThan(m.r * Double(w), t.sigma, "reach covers the shadow at \(t.x), \(t.y)")
                XCTAssertLessThan(m.r * Double(w), t.sigma * 5, "reach at \(t.x), \(t.y)")
            }
        }
        XCTAssertEqual(found.count, truth.count, "no spots that aren't there: \(found.map { ($0.x * Double(w), $0.y * Double(h), $0.depth) })")
        XCTAssertEqual(found.first?.depth ?? 0, found.map(\.depth).max() ?? 0, "deepest first")
    }

    func testCleanShootHasNoDust() {
        let acc = LookDust.Accumulator(width: w, height: h)
        for seed in 40...64 { acc.add(scene(UInt64(seed), w, h)) }
        XCTAssertEqual(acc.spots(), [])
    }

    func testSomethingInTheSamePictureEveryTimeIsNotDust() {
        // A locked-off series: one scene, a small dark thing in it, only the noise changes.
        let base = scene(7, w, h, noise: 0)
        let thing = dusted(base, [Dust(x: 200.5, y: 200.5, sigma: 2, depth: 0.3)])
        let acc = LookDust.Accumulator(width: w, height: h)
        for seed in 1...20 {
            var r = Rand(s: UInt64(seed) * 977)
            var f = thing
            for i in 0..<f.px.count { f.px[i] *= Float(1 + (r.next() - 0.5) * 0.01) }
            acc.add(f)
        }
        XCTAssertEqual(acc.spots(), [], "the same background under it every time: part of the picture")
    }

    func testTooFewFramesTellNothing() {
        let acc = LookDust.Accumulator(width: w, height: h)
        for seed in 1...4 { acc.add(dusted(scene(UInt64(seed), w, h), truth)) }
        XCTAssertEqual(acc.spots(), [])
        XCTAssertFalse(acc.add(LookDust.Plane(width: 10, height: 10)), "another size is refused")
        XCTAssertEqual(acc.frames, 4)
    }

    /// Three channels with a slight colour and real detail under the spot.
    private func colour(_ l: LookDust.Plane) -> [LookDust.Plane] {
        [0.9, 1.0, 1.15].map { k in LookDust.Plane(width: l.width, height: l.height, px: l.px.map { $0 * Float(k) }) }
    }

    private func error(_ a: [LookDust.Plane], _ b: [LookDust.Plane], cx: Double, cy: Double, radius: Double) -> (mean: Double, max: Double) {
        var sum = 0.0, top = 0.0, n = 0
        for c in a.indices {
            for y in 0..<a[c].height {
                for x in 0..<a[c].width {
                    let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                    guard dx * dx + dy * dy <= radius * radius else { continue }
                    let e = Double(abs(a[c][x, y] - b[c][x, y]) / max(0.01, b[c][x, y]))
                    sum += e; top = max(top, e); n += 1
                }
            }
        }
        return (sum / Double(max(1, n)), top)
    }

    func testLiftKeepsTheDetailUnderTheSpot() {
        // Fine texture under the dust: a clone or a fill would lose it, dividing the shadow out keeps it.
        var clean = scene(3, 160, 120)
        var r = Rand(s: 99)
        for y in 40..<80 { for x in 60..<100 { clean[x, y] *= Float(1 + (r.next() - 0.5) * 0.3) } }
        let clean3 = colour(clean)
        let d = Dust(x: 80.0, y: 60.0, sigma: 3, depth: 0.35)
        var photo = colour(dusted(clean, [d]))
        let before = error(photo, clean3, cx: d.x, cy: d.y, radius: 3 * d.sigma)
        // As found across a shoot at another aperture: the reach from a narrower shadow.
        let healed = LookDust.heal(&photo, cx: d.x, cy: d.y, reach: 2.5 * 2.2)
        let after = error(photo, clean3, cx: d.x, cy: d.y, radius: 3 * d.sigma)
        XCTAssertEqual(healed.method, .lift)
        XCTAssertEqual(healed.depth, d.depth, accuracy: 0.08)
        XCTAssertGreaterThan(before.max, 0.3)
        XCTAssertLessThan(after.mean, 0.02, "mean relative error inside the spot, before \(before)")
        XCTAssertLessThan(after.max, 0.08)
    }

    func testDeepSpotIsClonedAndBlended() {
        // Where dust shows most: open sky, a gradient with soft blotches.
        let clean = scene(5, 200, 150, noise: 0.001, texture: false)
        let clean3 = colour(clean)
        let d = Dust(x: 100, y: 75, sigma: 2.5, depth: 0.95)
        var photo = colour(dusted(clean, [d]))
        let before = error(photo, clean3, cx: d.x, cy: d.y, radius: 2.5 * d.sigma)
        let healed = LookDust.heal(&photo, cx: d.x, cy: d.y, reach: 2.5 * d.sigma)
        let after = error(photo, clean3, cx: d.x, cy: d.y, radius: 2.5 * d.sigma)
        XCTAssertEqual(healed.method, .clone)
        XCTAssertNotNil(healed.source)
        XCTAssertGreaterThan(before.mean, 0.25)
        XCTAssertLessThan(after.mean, 0.02, "before \(before)")
        XCTAssertLessThan(after.max, 0.15, "one cloned pixel may differ; the patch as a whole may not")
    }

    func testCloneSourceStaysClearOfOtherSpots() {
        let clean = scene(5, 200, 150, noise: 0.001)
        let luma = clean
        let region = LookDust.Disc(cx: 100, cy: 75, radius: 6, width: 200, height: 150)
        guard let free = LookDust.cloneSource(luma, region: region, avoid: []) else { return XCTFail("no source") }
        let avoid = [(x: Double(free.x), y: Double(free.y), r: 4.0)]
        guard let other = LookDust.cloneSource(luma, region: region, avoid: avoid) else { return XCTFail("no source") }
        let dx = Double(other.x - free.x), dy = Double(other.y - free.y)
        XCTAssertGreaterThan((dx * dx + dy * dy).squareRoot(), 4 + 6)
    }

    func testMembraneIsTheSmoothestSurface() {
        // Laplace's equation holds a plane exactly: a ramp on the ring comes back as the ramp inside.
        let disc = LookDust.Disc(cx: 20, cy: 20, radius: 8, width: 40, height: 40)
        let v = LookDust.membrane(disc) { x, y in Float(0.01 * Double(x) + 0.02 * Double(y) + 0.1) }
        for (j, p) in disc.inside.enumerated() {
            XCTAssertEqual(v[j], Float(0.01 * Double(p.x) + 0.02 * Double(p.y) + 0.1), accuracy: 1e-4)
        }
        XCTAssertFalse(disc.ring.isEmpty)
        // At the frame's edge the edge pixels hold the boundary.
        let corner = LookDust.Disc(cx: 1, cy: 1, radius: 4, width: 40, height: 40)
        XCTAssertFalse(corner.inside.contains { $0.x == 0 || $0.y == 0 })
    }

    func testBoxMeanMatchesTheSum() {
        var r = Rand(s: 5)
        let p = LookDust.Plane(width: 9, height: 7, px: (0..<63).map { _ in Float(r.next()) })
        let m = LookDust.boxMean(p, radius: 2)
        for y in 0..<7 {
            for x in 0..<9 {
                var s: Float = 0, n: Float = 0
                for yy in max(0, y - 2)...min(6, y + 2) { for xx in max(0, x - 2)...min(8, x + 2) { s += p[xx, yy]; n += 1 } }
                XCTAssertEqual(m[x, y], s / n, accuracy: 1e-5)
            }
        }
    }

    func testUprightTurnsWithThePhoto() {
        let s = LookDust.Spot(x: 0.1, y: 0.2, r: 0.01, depth: 0.1, hits: 5, frames: 6)
        XCTAssertEqual(s.upright(orientation: 1), s)
        XCTAssertEqual(s.upright(orientation: 3).x, 0.9, accuracy: 1e-12); XCTAssertEqual(s.upright(orientation: 3).y, 0.8, accuracy: 1e-12)
        // 6: turned clockwise to view. The stored top-left corner ends up top-right.
        XCTAssertEqual(s.upright(orientation: 6).x, 0.8, accuracy: 1e-12); XCTAssertEqual(s.upright(orientation: 6).y, 0.1, accuracy: 1e-12)
        XCTAssertEqual(s.upright(orientation: 8).x, 0.2, accuracy: 1e-12); XCTAssertEqual(s.upright(orientation: 8).y, 0.9, accuracy: 1e-12)
        XCTAssertEqual(s.upright(orientation: 6).r, s.r)
    }

    func testDevelopPatchUndoesTheShadow() {
        // A 20 % shadow 40 px across in a 1000 × 600 frame, near the top-left.
        let s = LookDust.Spot(x: 0.1, y: 0.2, r: 0.02, depth: 0.2, hits: 5, frames: 6)
        let p = try! XCTUnwrap(LookDust.patch(s, width: 1000, height: 600))
        XCTAssertEqual(Double(p.x0 + p.width / 2), 100, accuracy: 1.5); XCTAssertEqual(Double(p.y0 + p.height / 2), 120, accuracy: 1.5)
        let at = { (x: Int, y: Int) in p.gain[(y - p.y0) * p.width + (x - p.x0)] }
        XCTAssertEqual(Double(at(100, 120)), 1 / 0.8, accuracy: 0.01, "the centre is lifted by what the dust took")
        XCTAssertEqual(Double(at(p.x0, p.y0 + p.height / 2)), 1, accuracy: 0.01, "the box's edge is untouched")
        // Shadow times gain is flat: the spot is gone.
        for x in p.x0..<(p.x0 + p.width) {
            let dx = Double(x) + 0.5 - 100, dy = 0.5, sigma = 0.02 * 1000 / 2.5
            let shadow = 1 - 0.2 * exp(-(dx * dx + dy * dy) / (2 * sigma * sigma))
            XCTAssertEqual(shadow * Double(at(x, 120)), 1, accuracy: 1e-4)
        }
    }

    func testDevelopPatchStopsAtTheFrameAndTheDeepest() {
        let corner = LookDust.Spot(x: 0, y: 1, r: 0.02, depth: 0.95, hits: 5, frames: 6)
        let p = try! XCTUnwrap(LookDust.patch(corner, width: 500, height: 400))
        XCTAssertEqual(p.x0, 0); XCTAssertEqual(p.y0 + p.height, 400)
        XCTAssertLessThanOrEqual(Double(p.gain.max() ?? 0), 1 / (1 - LookDust.maxDevelopDepth) + 1e-4, "too deep to lift: capped")
        XCTAssertNil(LookDust.patch(LookDust.Spot(x: 3, y: 3, r: 0.01, depth: 0.2, hits: 1, frames: 1), width: 500, height: 400), "off the frame")
        XCTAssertNil(LookDust.patch(LookDust.Spot(x: 0.5, y: 0.5, r: 0.01, depth: 0, hits: 1, frames: 1), width: 500, height: 400))
    }

    func testRegistryStampFollowsTheSpots() {
        let reg = LookDust.Registry(), a = URL(fileURLWithPath: "/a.ARW")
        XCTAssertEqual(reg.stamp(for: a), 0)
        let s = LookDust.Spot(x: 0.1, y: 0.2, r: 0.01, depth: 0.1, hits: 5, frames: 6)
        reg.set([s], for: a)
        let one = reg.stamp(for: a)
        XCTAssertNotEqual(one, 0); XCTAssertEqual(reg.spots(for: URL(fileURLWithPath: "/x/../a.ARW")), [s], "the same file however it is spelt")
        let gen = reg.generation
        var moved = s; moved.x = 0.3
        reg.set([moved], for: a)
        XCTAssertNotEqual(reg.stamp(for: a), one); XCTAssertGreaterThan(reg.generation, gen)
        reg.set([], for: a)
        XCTAssertEqual(reg.stamp(for: a), 0)
    }
}
