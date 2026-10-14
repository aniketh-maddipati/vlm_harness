import Foundation

/// The selections Lumina finds in a photo by itself, for Edit's automatic masks (DESIGN-ASKS
/// Prompt 28): a subject, each person, each other object, and the background, the way Lightroom's
/// Select Subject / People / Objects / Background offer them. The finding is Vision's
/// (`SetsMasks`); this is the maths around it, Foundation only so it also runs in the Linux Swift
/// sandbox: masks as planes of 0 … 1, their algebra, the edge refinement against the photo, the
/// outline the page draws, and which mask is which.
///
/// Structure from RapidRAW (AGPL, ideas only, never code): a coarse model mask is snapped to the
/// photo's edges with a guided filter before use (`ai_processing.rs`, `fast_guided_filter`), and
/// masks combine by union, subtraction and intersection (`mask_generation.rs`, `SubMaskMode`).
/// The guided filter itself is He, Sun and Tang, "Guided Image Filtering" (ECCV 2010).
nonisolated enum LookMasks {
    /// One channel, row-major, `width × height`, values 0 … 1 (1 = selected).
    struct Plane: Equatable, Sendable {
        let width: Int
        let height: Int
        var values: [Float]

        init(width: Int, height: Int, fill: Float = 0) {
            self.width = max(0, width); self.height = max(0, height)
            values = [Float](repeating: fill, count: self.width * self.height)
        }

        init?(width: Int, height: Int, values: [Float]) {
            guard width > 0, height > 0, values.count == width * height else { return nil }
            self.width = width; self.height = height; self.values = values
        }

        subscript(x: Int, y: Int) -> Float {
            get { values[y * width + x] }
            set { values[y * width + x] = newValue }
        }

        var isEmpty: Bool { width == 0 || height == 0 }
    }

    /// What a found mask is, in the order the page lists them.
    enum Kind: String, Sendable, CaseIterable {
        case subject, person, object, background
    }

    /// A box in fractions of the photo (0 … 1, from the top left).
    struct Box: Equatable, Sendable {
        var x: Double, y: Double, w: Double, h: Double
    }

    /// A point in fractions of the photo (0 … 1, from the top left).
    struct Point: Equatable, Sendable {
        var x: Double, y: Double
    }

    /// One mask as the page gets it: what it is, how sure the finding is, where it is, how much of
    /// the photo it covers, and its outline (closed loops; a hole is a loop of its own, so the
    /// page fills them with the even-odd rule).
    struct Found: Equatable, Sendable {
        var id: String
        var kind: Kind
        var score: Double
        var box: Box
        var area: Double
        var outline: [[Point]]

        /// The bridge's answer for one mask (`lumina.masks`), numbers rounded to 4 places.
        var dictionary: [String: Any] {
            func r(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
            return ["id": id, "kind": kind.rawValue, "score": r(score),
                    "box": [r(box.x), r(box.y), r(box.w), r(box.h)], "area": r(area),
                    "outline": outline.map { loop in loop.map { [r($0.x), r($0.y)] } }]
        }
    }

    // MARK: Algebra (RapidRAW's sub-mask modes)

    static func union(_ a: Plane, _ b: Plane) -> Plane { combine(a, b) { max($0, $1) } }
    /// `a` without `b`.
    static func subtract(_ a: Plane, _ b: Plane) -> Plane { combine(a, b) { x, y in x * (1 - y) } }
    static func intersect(_ a: Plane, _ b: Plane) -> Plane { combine(a, b) { min($0, $1) } }

    static func invert(_ a: Plane) -> Plane {
        var out = a
        for i in out.values.indices { out.values[i] = 1 - out.values[i] }
        return out
    }

    private static func combine(_ a: Plane, _ b: Plane, _ f: (Float, Float) -> Float) -> Plane {
        precondition(a.width == b.width && a.height == b.height, "masks must be the same size")
        var out = a
        for i in out.values.indices { out.values[i] = f(a.values[i], b.values[i]) }
        return out
    }

    // MARK: Measures

    /// The fraction of the photo at or over `threshold`.
    static func area(_ p: Plane, threshold: Float = 0.5) -> Double {
        guard !p.isEmpty else { return 0 }
        return Double(p.values.reduce(0) { $0 + ($1 >= threshold ? 1 : 0) }) / Double(p.values.count)
    }

    /// The box around everything at or over `threshold`, nil when nothing is.
    static func box(_ p: Plane, threshold: Float = 0.5) -> Box? {
        var x0 = p.width, y0 = p.height, x1 = -1, y1 = -1
        for y in 0..<p.height {
            for x in 0..<p.width where p[x, y] >= threshold {
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            }
        }
        guard x1 >= x0, y1 >= y0 else { return nil }
        let w = Double(p.width), h = Double(p.height)
        return Box(x: Double(x0) / w, y: Double(y0) / h, w: Double(x1 - x0 + 1) / w, h: Double(y1 - y0 + 1) / h)
    }

    /// The mean of `values` where `mask` is at or over `threshold`: how salient a mask is, from a
    /// saliency plane of the same size. 0 for an empty mask.
    static func mean(_ values: Plane, inside mask: Plane, threshold: Float = 0.5) -> Double {
        precondition(values.width == mask.width && values.height == mask.height, "planes must be the same size")
        var sum = 0.0, n = 0
        for i in mask.values.indices where mask.values[i] >= threshold { sum += Double(values.values[i]); n += 1 }
        return n > 0 ? sum / Double(n) : 0
    }

    /// Intersection over union of two masks at `threshold`; 0 when both are empty.
    static func iou(_ a: Plane, _ b: Plane, threshold: Float = 0.5) -> Double {
        precondition(a.width == b.width && a.height == b.height, "masks must be the same size")
        var inter = 0, uni = 0
        for i in a.values.indices {
            let x = a.values[i] >= threshold, y = b.values[i] >= threshold
            if x && y { inter += 1 }
            if x || y { uni += 1 }
        }
        return uni > 0 ? Double(inter) / Double(uni) : 0
    }

    // MARK: Resampling and filtering

    /// Bilinear, pixel centres aligned (a plane resized to its own size is unchanged).
    static func resized(_ p: Plane, width: Int, height: Int) -> Plane {
        guard !p.isEmpty, width > 0, height > 0 else { return Plane(width: width, height: height) }
        if p.width == width && p.height == height { return p }
        var out = Plane(width: width, height: height)
        let sx = Double(p.width) / Double(width), sy = Double(p.height) / Double(height)
        for y in 0..<height {
            let fy = min(max((Double(y) + 0.5) * sy - 0.5, 0), Double(p.height - 1))
            let y0 = Int(fy), y1 = min(y0 + 1, p.height - 1), ty = Float(fy - Double(y0))
            for x in 0..<width {
                let fx = min(max((Double(x) + 0.5) * sx - 0.5, 0), Double(p.width - 1))
                let x0 = Int(fx), x1 = min(x0 + 1, p.width - 1), tx = Float(fx - Double(x0))
                let top = p[x0, y0] * (1 - tx) + p[x1, y0] * tx
                let bottom = p[x0, y1] * (1 - tx) + p[x1, y1] * tx
                out[x, y] = top * (1 - ty) + bottom * ty
            }
        }
        return out
    }

    /// The mean over a `(2r + 1)²` window, the window cut at the edges (so a flat plane stays flat).
    static func boxMean(_ p: Plane, radius r: Int) -> Plane {
        guard r > 0, !p.isEmpty else { return p }
        let w = p.width, h = p.height
        var rows = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            var sum: Double = 0
            for x in 0...min(r, w - 1) { sum += Double(p.values[y * w + x]) }
            for x in 0..<w {
                let lo = max(0, x - r), hi = min(w - 1, x + r)
                rows[y * w + x] = Float(sum / Double(hi - lo + 1))
                if x + r + 1 < w { sum += Double(p.values[y * w + x + r + 1]) }
                if x - r >= 0 { sum -= Double(p.values[y * w + x - r]) }
            }
        }
        var out = Plane(width: w, height: h)
        for x in 0..<w {
            var sum: Double = 0
            for y in 0...min(r, h - 1) { sum += Double(rows[y * w + x]) }
            for y in 0..<h {
                let lo = max(0, y - r), hi = min(h - 1, y + r)
                out.values[y * w + x] = Float(sum / Double(hi - lo + 1))
                if y + r + 1 < h { sum += Double(rows[(y + r + 1) * w + x]) }
                if y - r >= 0 { sum -= Double(rows[(y - r) * w + x]) }
            }
        }
        return out
    }

    /// The guided filter: `mask` smoothed except across the edges of `guide` (the photo's
    /// luminance, 0 … 1, the same size). A coarse mask's boundary moves onto the photo's own
    /// edges. `eps` is how strong an edge must be to hold the mask (smaller holds weaker edges).
    static func guided(_ mask: Plane, guide: Plane, radius: Int, eps: Float = 1e-3) -> Plane {
        precondition(mask.width == guide.width && mask.height == guide.height, "mask and guide must be the same size")
        guard radius > 0, !mask.isEmpty else { return mask }
        let n = mask.values.count
        var ii = guide, ip = guide
        for i in 0..<n { ii.values[i] = guide.values[i] * guide.values[i]; ip.values[i] = guide.values[i] * mask.values[i] }
        let mI = boxMean(guide, radius: radius), mP = boxMean(mask, radius: radius)
        let mII = boxMean(ii, radius: radius), mIP = boxMean(ip, radius: radius)
        var a = guide, b = guide
        for i in 0..<n {
            let varI = mII.values[i] - mI.values[i] * mI.values[i]
            let cov = mIP.values[i] - mI.values[i] * mP.values[i]
            a.values[i] = cov / (varI + eps)
            b.values[i] = mP.values[i] - a.values[i] * mI.values[i]
        }
        let mA = boxMean(a, radius: radius), mB = boxMean(b, radius: radius)
        var out = mask
        for i in 0..<n { out.values[i] = min(1, max(0, mA.values[i] * guide.values[i] + mB.values[i])) }
        return out
    }

    // MARK: Outlines

    /// The mask's outline at `threshold` as closed loops in fractions of the photo, largest first.
    /// Each loop follows the pixel edges between selected and unselected pixels (outer edges
    /// clockwise on screen, holes the other way), then is simplified to within `tolerance` pixels
    /// (Ramer–Douglas–Peucker). Loops enclosing fewer than `minArea` pixels are dropped as noise;
    /// at most `maxLoops` are kept. A loop's first point is not repeated at its end.
    static func outline(_ p: Plane, threshold: Float = 0.5, tolerance: Double = 1.0, minArea: Double = 16, maxLoops: Int = 24) -> [[Point]] {
        guard !p.isEmpty else { return [] }
        let w = p.width, h = p.height, vw = w + 1
        func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h && p[x, y] >= threshold }
        // Directed pixel edges, keyed by the vertex they leave: bit d for direction d
        // (0 right, 1 down, 2 left, 3 up), the selected pixel on the edge's right on screen.
        var out = [UInt8](repeating: 0, count: vw * (h + 1))
        for y in 0..<h {
            for x in 0..<w where inside(x, y) {
                if !inside(x, y - 1) { out[y * vw + x] |= 1 << 0 }
                if !inside(x + 1, y) { out[y * vw + x + 1] |= 1 << 1 }
                if !inside(x, y + 1) { out[(y + 1) * vw + x + 1] |= 1 << 2 }
                if !inside(x - 1, y) { out[(y + 1) * vw + x] |= 1 << 3 }
            }
        }
        func has(_ v: Int, _ d: Int) -> Bool { out[v] & UInt8(1 << d) != 0 }
        let dx = [1, 0, -1, 0], dy = [0, 1, 0, -1]
        var loops: [(area: Double, points: [(Double, Double)])] = []
        for start in out.indices where out[start] != 0 {
            while out[start] != 0 {
                var v = start
                var d = (0..<4).first(where: { has(start, $0) })!
                var corners: [(Double, Double)] = []
                var last = -1
                while true {
                    out[v] &= ~UInt8(1 << d)
                    if d != last { corners.append((Double(v % vw), Double(v / vw))) }
                    last = d
                    v += dx[d] + dy[d] * vw
                    if v == start { break }
                    // Turn right first, then straight, then left: a pinch between two diagonal
                    // pixels then keeps them as separate loops.
                    guard let next = [(d + 1) % 4, d, (d + 3) % 4].first(where: { has(v, $0) }) else { break }
                    d = next
                }
                if corners.count >= 3 {
                    var a2 = 0.0
                    for i in corners.indices {
                        let (x0, y0) = corners[i], (x1, y1) = corners[(i + 1) % corners.count]
                        a2 += x0 * y1 - x1 * y0
                    }
                    if abs(a2) / 2 >= minArea { loops.append((abs(a2) / 2, corners)) }
                }
            }
        }
        loops.sort { $0.area > $1.area }
        return loops.prefix(max(0, maxLoops)).map { loop in
            simplify(loop.points, tolerance: tolerance).map { Point(x: $0.0 / Double(w), y: $0.1 / Double(h)) }
        }
    }

    /// Ramer–Douglas–Peucker on a closed loop: split at the point farthest from the first, simplify
    /// both halves as open lines. Keeps at least three points.
    static func simplify(_ loop: [(Double, Double)], tolerance: Double) -> [(Double, Double)] {
        guard loop.count > 3, tolerance > 0 else { return loop }
        func dist(_ p: (Double, Double), _ q: (Double, Double)) -> Double { ((p.0 - q.0) * (p.0 - q.0) + (p.1 - q.1) * (p.1 - q.1)).squareRoot() }
        let far = loop.indices.max(by: { dist(loop[0], loop[$0]) < dist(loop[0], loop[$1]) })!
        func rdp(_ pts: ArraySlice<(Double, Double)>) -> [(Double, Double)] {
            guard pts.count > 2, let a = pts.first, let b = pts.last else { return Array(pts) }
            let len = dist(a, b)
            var worst = 0.0, at = pts.startIndex
            for i in pts.indices.dropFirst().dropLast() {
                let p = pts[i]
                let d = len == 0 ? dist(p, a) : abs((b.0 - a.0) * (a.1 - p.1) - (a.0 - p.0) * (b.1 - a.1)) / len
                if d > worst { worst = d; at = i }
            }
            guard worst > tolerance else { return [a, b] }
            return Array(rdp(pts[pts.startIndex...at]).dropLast()) + rdp(pts[at...pts.endIndex - 1])
        }
        let closed = loop + [loop[0]]
        let first = rdp(closed[0...far]), second = rdp(closed[far...closed.count - 1])
        let joined = Array(first.dropLast()) + Array(second.dropLast())
        return joined.count >= 3 ? joined : loop
    }

    // MARK: Which mask is which

    /// One region a finder returned, before it is named.
    struct Region: Sendable {
        var mask: Plane
        /// How sure the finder is, 0 … 1.
        var score: Double
        /// Mean saliency inside the mask, 0 … 1; nil when no saliency was measured.
        var saliency: Double?
    }

    /// Names what the finders returned, in the page's order. `people` are person instances;
    /// `objects` are foreground instances. An object that is mostly one of the people
    /// (IoU ≥ `sameAs`) is that person, not listed twice. The subject is the object or person
    /// that stands out most (saliency × √area, or area alone without saliency), listed first on
    /// its own as Lightroom lists Select Subject; it stays in its own list too. The background is
    /// everything outside every object and person, listed when it is between 2 % and 98 % of the
    /// photo. Regions under `minArea` of the photo are dropped.
    static func name(people: [Region], objects: [Region], sameAs: Double = 0.5, minArea: Double = 0.002,
                     tolerance: Double = 1.0) -> [Found] {
        let people = people.filter { area($0.mask) >= minArea }
        let objects = objects.filter { o in area(o.mask) >= minArea && !people.contains { iou($0.mask, o.mask) >= sameAs } }
        let all = people.map { (Kind.person, $0) } + objects.map { (Kind.object, $0) }
        guard let size = all.first?.1.mask else { return [] }
        func standout(_ r: Region) -> Double { let a = area(r.mask); return r.saliency.map { $0 * a.squareRoot() } ?? a }
        func found(_ id: String, _ kind: Kind, _ r: Region) -> Found? {
            guard let b = box(r.mask) else { return nil }
            return Found(id: id, kind: kind, score: min(1, max(0, r.score)), box: b, area: area(r.mask), outline: outline(r.mask, tolerance: tolerance))
        }
        var list: [Found] = []
        if let top = all.max(by: { standout($0.1) < standout($1.1) }), let s = found("subject", .subject, top.1) { list.append(s) }
        for (i, r) in people.enumerated() { if let f = found("person-\(i + 1)", .person, r) { list.append(f) } }
        for (i, r) in objects.enumerated() { if let f = found("object-\(i + 1)", .object, r) { list.append(f) } }
        var fg = Plane(width: size.width, height: size.height)
        for (_, r) in all { fg = union(fg, r.mask) }
        let bg = Region(mask: invert(fg), score: all.map { $0.1.score }.max() ?? 0, saliency: nil)
        let bgArea = area(bg.mask)
        if bgArea >= 0.02 && bgArea <= 0.98, let f = found("background", .background, bg) { list.append(f) }
        return list
    }
}

// MARK: Rasterising (adjustments inside a mask, DESIGN-ASKS Prompt 29)

nonisolated extension LookMasks {
    /// `outline` (closed loops in fractions of the photo from its top left, filled even-odd, as
    /// `Found.outline` has them) as a plane of `width × height` covering the whole photo, row 0 at
    /// the photo's top. Each pixel holds the share of it that is inside: exact along a row,
    /// `samples` lines down each row (4: an edge steps in quarters at worst). `feather`, a fraction
    /// of the plane's long edge, then softens the edge (two box passes, together about that wide), so the
    /// same feather is the same width of the photo at every size. The render blends a mask's
    /// adjustments through this (`LookPipeline.apply`).
    static func raster(_ outline: [[Point]], width: Int, height: Int, samples: Int = 4, feather: Double = 0) -> Plane {
        var p = Plane(width: width, height: height)
        guard width > 0, height > 0 else { return p }
        let w = Double(width), h = Double(height), n = max(1, min(16, samples))
        // The loops' edges in pixels, each listed under the rows it crosses. A horizontal edge
        // crosses no sample line; a loop of fewer than three points encloses nothing.
        var edges: [(x0: Double, y0: Double, x1: Double, y1: Double)] = []
        var rows = [[Int]](repeating: [], count: height)
        for loop in outline where loop.count >= 3 {
            for i in loop.indices {
                let a = loop[i], b = loop[(i + 1) % loop.count]
                guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite, a.y != b.y else { continue }
                let e = a.y < b.y ? (x0: a.x * w, y0: a.y * h, x1: b.x * w, y1: b.y * h) : (x0: b.x * w, y0: b.y * h, x1: a.x * w, y1: a.y * h)
                guard e.y1 > 0, e.y0 < h else { continue }
                let top = max(0, Int(e.y0.rounded(.down))), bottom = min(height - 1, Int(e.y1.rounded(.down)))
                guard top <= bottom else { continue }
                for r in top...bottom { rows[r].append(edges.count) }
                edges.append(e)
            }
        }
        var cover = [Double](repeating: 0, count: width)
        var runs = [Double](repeating: 0, count: width + 1)          // whole pixels inside, as a difference array
        var xs: [Double] = []
        let share = 1 / Double(n)
        for r in 0..<height where !rows[r].isEmpty {
            for i in 0..<width { cover[i] = 0 }
            for i in 0...width { runs[i] = 0 }
            for s in 0..<n {
                // A sample line crosses an edge that starts at or above it and ends below it (half
                // open), so a vertex on the line is counted once.
                let ys = Double(r) + (Double(s) + 0.5) * share
                xs.removeAll(keepingCapacity: true)
                for k in rows[r] {
                    let e = edges[k]
                    guard e.y0 <= ys, ys < e.y1 else { continue }
                    xs.append(e.x0 + (ys - e.y0) * (e.x1 - e.x0) / (e.y1 - e.y0))
                }
                xs.sort()
                // Even-odd: inside between the first crossing and the second, the third and the fourth, …
                var j = 0
                while j + 1 < xs.count {
                    let a = min(w, max(0, xs[j])), b = min(w, max(0, xs[j + 1]))
                    j += 2
                    guard b > a else { continue }
                    let ia = min(width - 1, Int(a.rounded(.down))), ib = Int(b.rounded(.down))
                    if ib <= ia { cover[ia] += (b - a) * share; continue }
                    cover[ia] += (Double(ia + 1) - a) * share
                    if ib > ia + 1 { runs[ia + 1] += share; runs[ib] -= share }
                    if ib < width { cover[ib] += (b - Double(ib)) * share }
                }
            }
            var run = 0.0
            for i in 0..<width {
                run += runs[i]
                p.values[r * width + i] = Float(min(1, max(0, cover[i] + run)))
            }
        }
        let radius = Int((max(0, feather.isFinite ? feather : 0) * Double(max(width, height)) / 4).rounded())
        if radius > 0 { p = boxMean(boxMean(p, radius: radius), radius: radius) }
        return p
    }

    /// The plane a mask is rasterised to for a picture where the whole photo is `width × height`
    /// pixels (either may be fractional): the smallest of 256, 512, 1024 and 2048 on the long edge
    /// that is at least the photo's, at most `cap`, with the photo's aspect. A few sizes only, so
    /// a cache holds one plane per size whatever the zoom or tier, and the drag tier gets a small one.
    static func rasterSize(photo width: Double, _ height: Double, cap: Int = 2048) -> (width: Int, height: Int) {
        let long = max(width, height)
        guard long.isFinite, long > 0, width > 0, height > 0 else { return (1, 1) }
        let edge = Double([256, 512, 1024, 2048].first { Double($0) >= long && $0 <= cap } ?? max(1, min(cap, 2048)))
        let s = edge / long
        return (max(1, Int((width * s).rounded())), max(1, Int((height * s).rounded())))
    }
}
