import Foundation

/// Sensor dust, found once across a shoot and lifted out of each photo.
///
/// Dust sits on the sensor's filter stack, so it darkens the same place in every frame from a body
/// until the sensor is cleaned. It is a soft, nearly neutral shadow: the light under it is dimmed,
/// not replaced, so the detail under a spot is still in the file. That gives two things a per-photo
/// spot tool doesn't have:
///
/// - **Finding.** Divide each frame by a blurred copy of itself and dust is a dip below 1 that stays
///   put while the scene changes. Averaged over many frames, only on their smooth areas (sky, walls,
///   out-of-focus backgrounds), scene content cancels and the spots remain. A dark thing that is
///   really in the picture (the same pole in a locked-off series) also stays put, so a spot must sit
///   on backgrounds that differ from frame to frame.
/// - **Lifting.** In each photo, fit how dark the spot is there (dust is deeper and smaller stopped
///   down, fainter and wider wide open) and divide the shadow out: the pixels under it are the
///   photo's own, not a clone or a prediction. A spot too deep to lift (little light got through)
///   is cloned from the best-matching nearby source and blended in the gradient domain, as a spot
///   heal does.
///
/// Positions are fractions of the frame **as stored** (sensor orientation, before the EXIF turn),
/// because that is where dust lives. `Spot.upright(orientation:)` turns one for a photo.
///
/// Ideas from RapidRAW's heal (`inpainting.rs`, a Poisson blend solved by SOR; AGPL, structure only,
/// AGENTS.md) and the plan in `notes/ai-masking-and-healing.md` (§2 "dust across a shoot", M2).
/// Foundation only: tested on Linux (`Tests/linux-swift`).
nonisolated enum LookDust {
    /// One channel of an image, row-major. For finding: linear luma in 0…1.
    struct Plane: Sendable {
        let width: Int
        let height: Int
        var px: [Float]

        init(width: Int, height: Int, px: [Float]) {
            precondition(width > 0 && height > 0 && px.count == width * height, "plane size")
            self.width = width; self.height = height; self.px = px
        }

        init(width: Int, height: Int, fill: Float = 0) { self.init(width: width, height: height, px: [Float](repeating: fill, count: width * height)) }

        subscript(x: Int, y: Int) -> Float {
            get { px[y * width + x] }
            set { px[y * width + x] = newValue }
        }
    }

    /// A dust spot. `x`, `y`: its centre as fractions of the stored frame's width and height;
    /// `r`: its reach (about 2.5 σ of its shadow) as a fraction of the width; `depth`: how much
    /// light it takes at its centre on average over the frames (0.1 = 10 % darker);
    /// `hits` of `frames`: the frames it showed in, of those smooth enough there to tell.
    struct Spot: Equatable, Codable, Sendable {
        var x: Double
        var y: Double
        var r: Double
        var depth: Double
        var hits: Int
        var frames: Int

        /// The same spot in a photo shown with EXIF `orientation` (1, 3, 6, 8; others as stored).
        /// `x`, `y` become fractions of the upright picture; `r` stays a fraction of the stored width.
        func upright(orientation: Int) -> Spot {
            var s = self
            switch orientation {
            case 3: s.x = 1 - x; s.y = 1 - y
            case 6: s.x = 1 - y; s.y = x          // stored top-left lands top-right
            case 8: s.x = y; s.y = 1 - x          // stored top-left lands bottom-left
            default: break
            }
            return s
        }

        var dictionary: [String: Any] { ["x": x, "y": y, "r": r, "depth": depth, "hits": hits, "frames": frames] }
    }

    struct Options: Sendable {
        /// The blur a frame is divided by, as a fraction of its width. Larger than any spot.
        var blurFraction = 1.0 / 64
        /// A pixel counts in a frame only where the scene around it is this smooth (mean |ratio − 1|
        /// over three blur radii). Edges and texture would swamp a few percent of dust.
        var smoothLimit: Float = 0.02
        /// Darker or brighter than this (linear luma) tells nothing: noise or clipping.
        var darkLimit: Float = 0.02
        var brightLimit: Float = 0.9
        /// The least average darkening a spot needs at its centre.
        var minDepth: Float = 0.02
        /// A frame "shows" the spot at a pixel when it is this much darker there.
        var hitDepth: Float = 0.02
        /// Share of the counted frames that must show it.
        var minHitShare: Float = 0.5
        /// Frames that must be smooth at a pixel before it can hold a spot.
        var minFrames = 5
        /// The backgrounds under a spot must differ across those frames (coefficient of variation of
        /// the blurred brightness), or it is something in the picture.
        var minBackgroundVariation: Float = 0.08
        /// The largest spot, as a fraction of the width (its radius). Larger is shading, not dust.
        var maxRadiusFraction = 1.0 / 50
        var minArea = 3

        init() {}
    }

    // MARK: Finding

    /// Adds frames one at a time (memory stays a few planes, however long the shoot), then names
    /// the spots. All frames must have the same stored size: group a shoot by body and size first.
    /// Not thread-safe; one per body.
    final class Accumulator {
        let width: Int
        let height: Int
        let options: Options
        private(set) var frames = 0
        private var sum: [Float]       // Σ ratio over the frames smooth there
        private var count: [UInt16]    // frames smooth there
        private var hits: [UInt16]     // of those, frames darker than hitDepth
        private var bSum: [Float]      // Σ blurred brightness, for the background check
        private var bSq: [Float]       // Σ blurred brightness²

        init(width: Int, height: Int, options: Options = Options()) {
            precondition(width > 0 && height > 0, "accumulator size")
            self.width = width; self.height = height; self.options = options
            let n = width * height
            sum = [Float](repeating: 0, count: n); count = [UInt16](repeating: 0, count: n); hits = count
            bSum = sum; bSq = sum
        }

        var blurRadius: Int { max(3, Int((Double(width) * options.blurFraction).rounded())) }

        /// Adds one frame (linear luma, as stored). A frame of another size is refused (false).
        @discardableResult
        func add(_ luma: Plane) -> Bool {
            guard luma.width == width, luma.height == height, frames < Int(UInt16.max) else { return false }
            let r = blurRadius
            let blur = LookDust.boxMean(luma, radius: r)
            var ratio = Plane(width: width, height: height, fill: 1)
            var dev = Plane(width: width, height: height, fill: 1)
            for i in 0..<luma.px.count {
                let b = blur.px[i], l = luma.px[i]
                guard b > options.darkLimit, b < options.brightLimit, l < options.brightLimit else { continue }
                ratio.px[i] = l / b
                dev.px[i] = abs(ratio.px[i] - 1)
            }
            // Texture over a wider window than any spot, so a spot doesn't count as texture.
            let texture = LookDust.boxMean(dev, radius: 3 * r)
            for i in 0..<luma.px.count where texture.px[i] < options.smoothLimit {
                let b = blur.px[i]
                guard b > options.darkLimit, b < options.brightLimit, luma.px[i] < options.brightLimit else { continue }
                let q = min(1.5, max(0.5, ratio.px[i]))
                sum[i] += q
                count[i] &+= 1
                if q < 1 - options.hitDepth { hits[i] &+= 1 }
                bSum[i] += b
                bSq[i] += b * b
            }
            frames += 1
            return true
        }

        /// The average darkening at each pixel (0 where too few frames could tell).
        func depthMap() -> Plane {
            var d = Plane(width: width, height: height)
            for i in 0..<d.px.count where Int(count[i]) >= options.minFrames {
                d.px[i] = max(0, 1 - sum[i] / Float(count[i]))
            }
            return d
        }

        /// The spots, deepest first.
        func spots() -> [Spot] {
            let depth = depthMap()
            var candidate = [Bool](repeating: false, count: width * height)
            for i in 0..<candidate.count where Int(count[i]) >= options.minFrames {
                candidate[i] = depth.px[i] >= options.minDepth && Float(hits[i]) >= options.minHitShare * Float(count[i])
            }
            let maxR = Double(width) * options.maxRadiusFraction
            let maxArea = Int(Double.pi * maxR * maxR)
            var out: [Spot] = []
            for comp in LookDust.components(candidate, width: width, height: height) {
                guard comp.count >= options.minArea, comp.count <= maxArea else { continue }
                // Weighted by depth: the centre and spread of the shadow.
                var w = 0.0, sx = 0.0, sy = 0.0, peak = 0, peakDepth: Float = 0
                for i in comp {
                    let d = Double(depth.px[i]); w += d
                    sx += d * Double(i % width); sy += d * Double(i / width)
                    if depth.px[i] > peakDepth { peakDepth = depth.px[i]; peak = i }
                }
                guard w > 0, peakDepth >= options.minDepth * 1.5 else { continue }
                let cx = sx / w, cy = sy / w
                var m2 = 0.0
                for i in comp {
                    let dx = Double(i % width) - cx, dy = Double(i / width) - cy
                    m2 += Double(depth.px[i]) * (dx * dx + dy * dy)
                }
                // m2 / w is the variance of the part above the threshold: a floor under σ. A spot is
                // at least a pixel and a half across.
                let sigma = max((m2 / w / 2).squareRoot(), (Double(comp.count) / Double.pi).squareRoot() / 2, 0.75)
                guard 2.5 * sigma <= maxR else { continue }
                // Something in the picture sits on the same background every time.
                let n = Float(count[peak])
                let mean = bSum[peak] / n
                let variance = max(0, bSq[peak] / n - mean * mean)
                guard mean > 0, variance.squareRoot() / mean >= options.minBackgroundVariation else { continue }
                out.append(Spot(x: (cx + 0.5) / Double(width), y: (cy + 0.5) / Double(height), r: 2.5 * sigma / Double(width),
                                depth: Double(peakDepth), hits: Int(hits[peak]), frames: Int(count[peak])))
            }
            return out.sorted { $0.depth > $1.depth }
        }
    }

    // MARK: Lifting

    /// How a spot was healed in one photo.
    enum Method: String, Sendable { case lift, clone, none }

    struct Healed: Equatable, Sendable {
        var method: Method
        /// The fitted darkening at the centre in this photo (lift), or the source centre in pixels (clone).
        var depth: Double
        var source: (x: Int, y: Int)?

        static func == (a: Healed, b: Healed) -> Bool {
            a.method == b.method && a.depth == b.depth && a.source?.x == b.source?.x && a.source?.y == b.source?.y
        }
    }

    /// Where at least this share of the light got through, the spot is lifted (divided out) alone.
    /// Below `noLight` the pixel is cloned; between, the two are blended.
    static let trustLight = 0.4
    static let noLight = 0.15

    /// Heals one spot in place in linear RGB `channels` (all the same size; the spot in that image's
    /// pixels: `cx`, `cy` centre, `reach` ≈ 2.5 σ of the shadow as found). `avoid`: other spots, in
    /// the same pixels, a clone source must not overlap.
    @discardableResult
    static func heal(_ channels: inout [Plane], cx: Double, cy: Double, reach: Double,
                     avoid: [(x: Double, y: Double, r: Double)] = []) -> Healed {
        guard let first = channels.first, reach > 0 else { return Healed(method: .none, depth: 0, source: nil) }
        let w = first.width, h = first.height
        // The fit looks a little past the reach (dust is wider and fainter wide open), but no
        // further: the surroundings carried across must be smooth, and every pixel more risks an edge.
        let region = Disc(cx: cx, cy: cy, radius: 1.4 * reach + 1, width: w, height: h)
        guard region.inside.count >= 4, !region.ring.isEmpty else { return Healed(method: .none, depth: 0, source: nil) }
        let luma = lumaPlane(channels)
        // What the light would be without the spot: the surroundings carried smoothly across.
        let bare = membrane(region, boundary: { luma[$0, $1] })
        // Fit a = 1 − k·g for a few widths of the shadow, keep the best.
        var best: (k: Double, sigma: Double, err: Double) = (0, reach / 2.5, .infinity)
        for scale in [0.75, 1.0, 1.25] {
            let sigma = reach / 2.5 * scale
            var num = 0.0, den = 0.0
            for (j, p) in region.inside.enumerated() {
                let b = Double(bare[j]); guard b > 1e-4 else { continue }
                let a = Double(luma[p.x, p.y]) / b
                let g = gauss(p, cx, cy, sigma)
                num += (1 - a) * g; den += g * g
            }
            guard den > 0 else { continue }
            let k = min(0.98, max(0, num / den))
            var err = 0.0
            for (j, p) in region.inside.enumerated() {
                let b = Double(bare[j]); guard b > 1e-4 else { continue }
                let e = Double(luma[p.x, p.y]) / b - (1 - k * gauss(p, cx, cy, sigma))
                err += e * e
            }
            if err < best.err { best = (k, sigma, err) }
        }
        let lifted: [[Float]] = channels.map { plane in
            region.inside.map { p in plane[p.x, p.y] / Float(max(0.02, 1 - best.k * gauss(p, cx, cy, best.sigma))) }
        }
        if 1 - best.k >= trustLight {
            for c in channels.indices { for (j, p) in region.inside.enumerated() { channels[c][p.x, p.y] = lifted[c][j] } }
            return Healed(method: .lift, depth: best.k, source: nil)
        }
        // Where little light got through, dividing it out would mostly raise noise: clone there, and
        // blend toward the lifted pixels as the light under the spot comes back.
        let patch = Disc(cx: cx, cy: cy, radius: 2.5 * max(best.sigma, reach / 2.5) + 1, width: w, height: h)
        guard patch.inside.count >= 1, let src = cloneSource(luma, region: patch, avoid: avoid) else {
            for c in channels.indices { for (j, p) in region.inside.enumerated() { channels[c][p.x, p.y] = lifted[c][j] } }
            return Healed(method: .lift, depth: best.k, source: nil)
        }
        let dx = src.x - Int(cx.rounded()), dy = src.y - Int(cy.rounded())
        var cloned: [[Float]] = []
        for c in channels.indices {
            let plane = channels[c]
            // Gradient-domain clone: the source's detail, shifted so its edge meets the photo's.
            let offset = membrane(patch, boundary: { plane[$0, $1] - plane[$0 + dx, $1 + dy] })
            cloned.append(patch.inside.enumerated().map { j, p in max(0, plane[p.x + dx, p.y + dy] + offset[j]) })
        }
        var inPatch: [Int: Int] = [:]
        for (j, p) in patch.inside.enumerated() { inPatch[p.y * w + p.x] = j }
        for (j, p) in region.inside.enumerated() {
            let t = 1 - best.k * gauss(p, cx, cy, best.sigma)
            let keep = Float(smoothstep(noLight, trustLight, t))
            for c in channels.indices {
                if let k = inPatch[p.y * w + p.x] {
                    channels[c][p.x, p.y] = keep * lifted[c][j] + (1 - keep) * cloned[c][k]
                } else {
                    channels[c][p.x, p.y] = lifted[c][j]
                }
            }
        }
        return Healed(method: .clone, depth: best.k, source: src)
    }

    /// The pixels of a disc, and the one-pixel ring just outside it that holds its boundary.
    struct Disc {
        let inside: [(x: Int, y: Int)]
        let ring: [(x: Int, y: Int)]
        let box: (x0: Int, y0: Int, x1: Int, y1: Int)   // inclusive, ring included

        init(cx: Double, cy: Double, radius: Double, width: Int, height: Int) {
            let x0 = max(0, Int((cx - radius - 1).rounded(.down))), x1 = min(width - 1, Int((cx + radius + 1).rounded(.up)))
            let y0 = max(0, Int((cy - radius - 1).rounded(.down))), y1 = min(height - 1, Int((cy + radius + 1).rounded(.up)))
            var inside: [(x: Int, y: Int)] = [], ring: [(x: Int, y: Int)] = []
            func within(_ x: Int, _ y: Int) -> Bool {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                return dx * dx + dy * dy <= radius * radius
            }
            if x0 <= x1 && y0 <= y1 {
                for y in y0...y1 {
                    for x in x0...x1 {
                        // The frame's edge is a boundary too: a disc never reaches the outermost pixels.
                        let edge = x == 0 || y == 0 || x == width - 1 || y == height - 1
                        if within(x, y) && !edge { inside.append((x, y)); continue }
                        let touches = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { within(x + $0.0, y + $0.1) }
                        if touches || (edge && within(x, y)) { ring.append((x, y)) }
                    }
                }
            }
            self.inside = inside; self.ring = ring; box = (x0, y0, x1, y1)
        }
    }

    /// Solves Laplace's equation inside the disc with `boundary` held on its ring: the smoothest
    /// surface through the surroundings. Returns one value per `disc.inside` pixel. Starts from the
    /// distance-weighted mean of the ring, then successive over-relaxation (RapidRAW solves its heal
    /// the same way; ω and the stopping rule are ours).
    static func membrane(_ disc: Disc, boundary: (Int, Int) -> Float) -> [Float] {
        let (x0, y0, x1, y1) = disc.box
        let bw = x1 - x0 + 1, bh = y1 - y0 + 1
        var v = [Float](repeating: 0, count: bw * bh)
        var fixed = [Bool](repeating: false, count: bw * bh)
        var free = [Bool](repeating: false, count: bw * bh)
        var ringValues: [(x: Double, y: Double, v: Float)] = []
        for p in disc.ring {
            let i = (p.y - y0) * bw + (p.x - x0)
            v[i] = boundary(p.x, p.y); fixed[i] = true
            ringValues.append((Double(p.x), Double(p.y), v[i]))
        }
        for p in disc.inside {
            let i = (p.y - y0) * bw + (p.x - x0)
            free[i] = true
            var ws = 0.0, vs = 0.0
            for q in ringValues {
                let d2 = (q.x - Double(p.x)) * (q.x - Double(p.x)) + (q.y - Double(p.y)) * (q.y - Double(p.y))
                let wq = 1 / max(1, d2 * d2)
                ws += wq; vs += wq * Double(q.v)
            }
            v[i] = ws > 0 ? Float(vs / ws) : 0
        }
        let omega: Float = 1.8
        let span = max(bw, bh)
        for _ in 0..<max(50, 4 * span) {
            var change: Float = 0
            for y in 0..<bh {
                for x in 0..<bw where free[y * bw + x] {
                    var s: Float = 0, n: Float = 0
                    for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < bw && ny < bh {
                        let j = ny * bw + nx
                        if fixed[j] || free[j] { s += v[j]; n += 1 }
                    }
                    guard n > 0 else { continue }
                    let i = y * bw + x
                    let next = v[i] + omega * (s / n - v[i])
                    change = max(change, abs(next - v[i]))
                    v[i] = next
                }
            }
            if change < 1e-6 { break }
        }
        return disc.inside.map { v[($0.y - y0) * bw + ($0.x - x0)] }
    }

    /// The nearby place whose surroundings best match the spot's ring (sum of squared differences
    /// on luma), searched on a grid between 2.5 and 6 disc radii away (a pixel apart for small
    /// spots, a quarter radius for large ones), nearer winning a tie. Nil when nothing fits in the
    /// frame clear of `avoid`.
    static func cloneSource(_ luma: Plane, region: Disc, avoid: [(x: Double, y: Double, r: Double)]) -> (x: Int, y: Int)? {
        let (x0, y0, x1, y1) = region.box
        let cx = Int((Double(x0 + x1) / 2).rounded()), cy = Int((Double(y0 + y1) / 2).rounded())
        let radius = Double(max(x1 - x0, y1 - y0)) / 2
        let near = 2.5 * radius, far = 6 * radius
        let step = max(1, Int(radius / 4))
        let reach = Int(far.rounded(.up))
        // Matched on a band around the patch, a third of its radius wide (at least 2 px): a one-pixel
        // ring matches level and slope but not curvature, and a valley cloned onto a ridge shows.
        let band = max(2.0, radius / 3)
        var around: [(x: Int, y: Int)] = []
        for y in max(0, Int(Double(cy) - radius - band)) ... min(luma.height - 1, Int(Double(cy) + radius + band)) {
            for x in max(0, Int(Double(cx) - radius - band)) ... min(luma.width - 1, Int(Double(cx) + radius + band)) {
                let ex = Double(x - cx), ey = Double(y - cy)
                let d = (ex * ex + ey * ey).squareRoot()
                if d > radius - 0.5 && d <= radius + band { around.append((x, y)) }
            }
        }
        let bandReach = Int((radius + band).rounded(.up))
        var best: (x: Int, y: Int, score: Double)?
        for dy in stride(from: -reach, through: reach, by: step) {
            for dx in stride(from: -reach, through: reach, by: step) {
                let d = (Double(dx * dx + dy * dy)).squareRoot()
                guard d >= near, d <= far else { continue }
                // The whole patch and its ring must land inside the frame.
                guard x0 + dx >= 0, y0 + dy >= 0, x1 + dx < luma.width, y1 + dy < luma.height,
                      cx + dx - bandReach >= 0, cy + dy - bandReach >= 0, cx + dx + bandReach < luma.width, cy + dy + bandReach < luma.height else { continue }
                let sx = cx + dx, sy = cy + dy
                let clear = avoid.allSatisfy { o in
                    let ex = o.x - Double(sx), ey = o.y - Double(sy)
                    return (ex * ex + ey * ey).squareRoot() > o.r + radius
                }
                guard clear else { continue }
                var score = 0.0
                for p in around {
                    let e = Double(luma[p.x, p.y] - luma[p.x + dx, p.y + dy]); score += e * e
                }
                // A slight preference for nearer sources: same light, same focus.
                score *= 1 + 0.02 * d / radius
                if best == nil || score < best!.score { best = (sx, sy, score) }
            }
        }
        return best.map { ($0.x, $0.y) }
    }

    // MARK: Helpers

    /// Rec. 709 luma of linear RGB planes (a single plane is its own luma).
    static func lumaPlane(_ channels: [Plane]) -> Plane {
        guard channels.count >= 3 else { return channels[0] }
        var out = Plane(width: channels[0].width, height: channels[0].height)
        for i in 0..<out.px.count {
            out.px[i] = 0.2126 * channels[0].px[i] + 0.7152 * channels[1].px[i] + 0.0722 * channels[2].px[i]
        }
        return out
    }

    /// sRGB-encoded 0…1 to linear light.
    static func linear(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4) }

    /// The mean over a (2r+1)² square, clamped at the edges (divided by the pixels it covers), from a
    /// summed-area table in Double so a large frame keeps its precision.
    static func boxMean(_ p: Plane, radius r: Int) -> Plane {
        let w = p.width, h = p.height
        var table = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h {
            var row = 0.0
            for x in 0..<w {
                row += Double(p.px[y * w + x])
                table[(y + 1) * (w + 1) + x + 1] = table[y * (w + 1) + x + 1] + row
            }
        }
        var out = Plane(width: w, height: h)
        for y in 0..<h {
            let ya = max(0, y - r), yb = min(h - 1, y + r) + 1
            for x in 0..<w {
                let xa = max(0, x - r), xb = min(w - 1, x + r) + 1
                let s = table[yb * (w + 1) + xb] - table[ya * (w + 1) + xb] - table[yb * (w + 1) + xa] + table[ya * (w + 1) + xa]
                out.px[y * w + x] = Float(s / Double((yb - ya) * (xb - xa)))
            }
        }
        return out
    }

    /// 8-connected groups of true pixels, each as pixel indices.
    static func components(_ mask: [Bool], width: Int, height: Int) -> [[Int]] {
        var seen = [Bool](repeating: false, count: mask.count)
        var out: [[Int]] = []
        for start in 0..<mask.count where mask[start] && !seen[start] {
            var group: [Int] = [], stack = [start]
            seen[start] = true
            while let i = stack.popLast() {
                group.append(i)
                let x = i % width, y = i / width
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let j = ny * width + nx
                        if mask[j] && !seen[j] { seen[j] = true; stack.append(j) }
                    }
                }
            }
            out.append(group)
        }
        return out
    }

    static func smoothstep(_ a: Double, _ b: Double, _ v: Double) -> Double {
        let t = min(1, max(0, (v - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private static func gauss(_ p: (x: Int, y: Int), _ cx: Double, _ cy: Double, _ sigma: Double) -> Double {
        let dx = Double(p.x) + 0.5 - cx, dy = Double(p.y) + 0.5 - cy
        return exp(-(dx * dx + dy * dy) / (2 * sigma * sigma))
    }
}
