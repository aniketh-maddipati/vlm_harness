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
        case subject, person, object, sky, background
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
    /// photo. Regions under `minArea` of the photo are dropped. `sky` (from `sky(red:green:blue:)`)
    /// is listed after the objects and before the background, id "sky". The background is not
    /// cut by the sky: Lightroom's Select Sky and Select Background are separate selections that
    /// overlap, and someone who wants the land alone subtracts one from the other.
    static func name(people: [Region], objects: [Region], sky: Region? = nil, sameAs: Double = 0.5, minArea: Double = 0.002,
                     tolerance: Double = 1.0) -> [Found] {
        let people = people.filter { area($0.mask) >= minArea }
        let objects = objects.filter { o in area(o.mask) >= minArea && !people.contains { iou($0.mask, o.mask) >= sameAs } }
        let all = people.map { (Kind.person, $0) } + objects.map { (Kind.object, $0) }
        let sky = sky.flatMap { area($0.mask) >= minArea ? $0 : nil }
        guard let size = all.first?.1.mask ?? sky?.mask else { return [] }
        func standout(_ r: Region) -> Double { let a = area(r.mask); return r.saliency.map { $0 * a.squareRoot() } ?? a }
        func found(_ id: String, _ kind: Kind, _ r: Region) -> Found? {
            guard let b = box(r.mask) else { return nil }
            return Found(id: id, kind: kind, score: min(1, max(0, r.score)), box: b, area: area(r.mask), outline: outline(r.mask, tolerance: tolerance))
        }
        var list: [Found] = []
        if let top = all.max(by: { standout($0.1) < standout($1.1) }), let s = found("subject", .subject, top.1) { list.append(s) }
        for (i, r) in people.enumerated() { if let f = found("person-\(i + 1)", .person, r) { list.append(f) } }
        for (i, r) in objects.enumerated() { if let f = found("object-\(i + 1)", .object, r) { list.append(f) } }
        if let sky, let f = found("sky", .sky, sky) { list.append(f) }
        var fg = Plane(width: size.width, height: size.height)
        for (_, r) in all { fg = union(fg, r.mask) }
        let bg = Region(mask: invert(fg), score: all.map { $0.1.score }.max() ?? 0, saliency: nil)
        let bgArea = area(bg.mask)
        if bgArea >= 0.02 && bgArea <= 0.98, let f = found("background", .background, bg) { list.append(f) }
        return list
    }

    // MARK: Sky

    /// The scene labels of Vision's classifier (`VNClassifyImageRequest`, on the Mac) that say a
    /// photo shows sky; `SetsMasks` looks for sky only when one of them reaches `skyThreshold`.
    /// Vision has no sky segmentation for an arbitrary photo, so the label is the gate and
    /// `sky(red:green:blue:)` is the finding. Names from the classifier's taxonomy as documented;
    /// a name this Mac's taxonomy lacks never matches, so the list can only be too short, never
    /// wrong (check against `supportedIdentifiers()` on a Mac). Add a label here to widen the gate.
    static let skyLabels: Set<String> = ["sky", "blue_sky", "cloudy", "sunset_sunrise", "rainbow", "storm"]

    /// How sure the classifier must be of a sky label. Its confidences are per label, not shared
    /// out between labels (a landscape is "outdoor", "sky" and "mountain" at once), so this is a
    /// floor on the label alone. Lower runs the finder on more photos; on one without sky it
    /// mostly returns nil anyway (it needs smooth, sky-coloured pixels along the top).
    static let skyThreshold: Float = 0.3

    /// The gate: the highest confidence among `labels` (the classifier's, name → confidence) that
    /// is one of `names` at or over `threshold`; nil when none is, and there is no sky to look for.
    static func skyScore(_ labels: [String: Float], among names: Set<String> = skyLabels, threshold: Float = skyThreshold) -> Double? {
        labels.filter { names.contains($0.key) && $0.value >= threshold }.values.max().map { Double(min(1, max(0, $0))) }
    }

    /// How sky-like each pixel is, 0 … 1, from its colour and how smooth its neighbourhood is
    /// (planes 0 … 1, sRGB encoded, one size). Colour is the best of three skies: blue (blue over
    /// red and not under green, not darker than twilight), overcast (bright and nearly neutral)
    /// and sunset (bright, red or blue over green: orange, pink, purple). Green over both red and blue counts against
    /// it (foliage, grass). Smoothness is the local standard deviation of luminance over a
    /// `(2r + 1)²` window, `r` = long edge / 256 (at least 2): smooth under 0.012, texture over
    /// 0.04. Sky is a gentle gradient (a JPEG's noise in it is well under 0.012); ground is texture.
    static func skyLikelihood(red: Plane, green: Plane, blue: Plane) -> Plane {
        let y = skyLuma(red: red, green: green, blue: blue)
        let c = skyColour(red: red, green: green, blue: blue, luma: y), s = skySmooth(y)
        var out = c
        for i in out.values.indices { out.values[i] = c.values[i] * s.values[i] }
        return out
    }

    /// The sky in a photo, as a mask of its size (soft at the edge), or nil when it is under
    /// `minArea` of the photo. Planes 0 … 1, sRGB encoded, one size (the preview at mask size).
    /// Lightroom's Select Sky without a model:
    ///
    /// 1. Each pixel's likelihood (`skyLikelihood`); 0.5 and over is a candidate.
    /// 2. The sky is the candidates connected (4-way) to the top 2 % of rows: sky is what the photo
    ///    looks up into. A candidate patch apart from it (sky between branches, under an arch) joins
    ///    when its mean colour is within 0.12 of the sky's and it starts above the sky's lowest row;
    ///    a blue car below the horizon does not.
    /// 3. Gaps under ~6 px (at 1024) are closed (a dilation, then an erosion); pixels beside the
    ///    sky that are sky-coloured but were refused as texture (next to a twig, a cloud's edge)
    ///    join it; holes are filled: any the sky encloses (a cloud, a bird), and small ones (under
    ///    2 % of the photo) it encloses against the top edge. A hole touching the photo's left,
    ///    right or bottom edge is ground and stays out.
    /// 4. `refine`: the edge is snapped to the photo's luminance (`guided`, radius long edge / 128),
    ///    so a skyline and the gaps in a tree are followed, as the other masks' edges are.
    ///
    /// Deterministic: box filters and flood fills, a dozen passes over the pixels.
    static func sky(red: Plane, green: Plane, blue: Plane, refine: Bool = true, minArea: Double = 0.03) -> Plane? {
        precondition(red.width == green.width && red.width == blue.width && red.height == green.height && red.height == blue.height,
                     "colour planes must be the same size")
        let w = red.width, h = red.height, n = w * h, long = max(w, h)
        guard w > 1, h > 1 else { return nil }
        let y = skyLuma(red: red, green: green, blue: blue)
        let colour = skyColour(red: red, green: green, blue: blue, luma: y), smooth = skySmooth(y)
        var cand = [Bool](repeating: false, count: n)
        for i in 0..<n { cand[i] = colour.values[i] * smooth.values[i] >= 0.5 }

        // 2. Connected to the top, and the patches that match it.
        let parts = skyComponents(cand, width: w, height: h)
        var isSky = [Bool](repeating: false, count: parts.count)
        for i in 0..<(max(1, h / 50) * w) where parts.of[i] >= 0 { isSky[Int(parts.of[i])] = true }
        guard isSky.contains(true) else { return nil }
        var sum = [(r: Double, g: Double, b: Double, n: Double)](repeating: (0, 0, 0, 0), count: parts.count)
        var top = [Int](repeating: h, count: parts.count)
        var bottom = 0
        for i in 0..<n where parts.of[i] >= 0 {
            let l = Int(parts.of[i])
            sum[l].r += Double(red.values[i]); sum[l].g += Double(green.values[i]); sum[l].b += Double(blue.values[i]); sum[l].n += 1
            top[l] = min(top[l], i / w)
            if isSky[l] { bottom = max(bottom, i / w) }
        }
        var all = (r: 0.0, g: 0.0, b: 0.0, n: 0.0)
        for l in 0..<parts.count where isSky[l] { all.r += sum[l].r; all.g += sum[l].g; all.b += sum[l].b; all.n += sum[l].n }
        for l in 0..<parts.count where !isSky[l] && top[l] < bottom {
            let dr = sum[l].r / sum[l].n - all.r / all.n, dg = sum[l].g / sum[l].n - all.g / all.n, db = sum[l].b / sum[l].n - all.b / all.n
            if (dr * dr + dg * dg + db * db).squareRoot() <= 0.12 { isSky[l] = true }
        }
        var m = Plane(width: w, height: h)
        for i in 0..<n where parts.of[i] >= 0 && isSky[Int(parts.of[i])] { m.values[i] = 1 }

        // 3. Close small gaps, take in sky-coloured neighbours, fill holes.
        let gap = max(1, long / 341)
        m = skyBinary(boxMean(skyBinary(boxMean(m, radius: gap), over: 0.001), radius: gap), over: 0.999)
        let beside = skyBinary(boxMean(m, radius: 2 * max(1, long / 256)), over: 0.001)
        for i in 0..<n where beside.values[i] == 1 && colour.values[i] >= 0.5 { m.values[i] = 1 }
        let holes = skyComponents(m.values.map { $0 < 0.5 }, width: w, height: h)
        var edge = [UInt8](repeating: 0, count: holes.count)            // bit 0: the top; bit 1: left, right or bottom
        var size = [Int](repeating: 0, count: holes.count)
        for i in 0..<n where holes.of[i] >= 0 {
            let l = Int(holes.of[i]), x = i % w, row = i / w
            size[l] += 1
            if row == 0 { edge[l] |= 1 }
            if x == 0 || x == w - 1 || row == h - 1 { edge[l] |= 2 }
        }
        for i in 0..<n where holes.of[i] >= 0 {
            let l = Int(holes.of[i])
            if edge[l] == 0 || (edge[l] == 1 && Double(size[l]) < 0.02 * Double(n)) { m.values[i] = 1 }
        }

        // 4. Snap the edge to the photo.
        if refine { m = guided(m, guide: y, radius: max(2, long / 128)) }
        return area(m) >= minArea ? m : nil
    }

    /// Rec. 709 weights on the encoded values: a guide, not a measurement.
    private static func skyLuma(red: Plane, green: Plane, blue: Plane) -> Plane {
        var y = red
        for i in y.values.indices { y.values[i] = 0.2126 * red.values[i] + 0.7152 * green.values[i] + 0.0722 * blue.values[i] }
        return y
    }

    /// 0 at or under `lo`, 1 at or over `hi`, linear between.
    private static func skyRamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float { min(1, max(0, (v - lo) / (hi - lo))) }

    private static func skyColour(red: Plane, green: Plane, blue: Plane, luma: Plane) -> Plane {
        var out = luma
        for i in out.values.indices {
            let r = red.values[i], g = green.values[i], b = blue.values[i], y = luma.values[i]
            let chroma = max(r, g, b) - min(r, g, b)
            let blueSky = skyRamp(b - r, 0.03, 0.12) * skyRamp(b - g, -0.06, 0) * skyRamp(y, 0.08, 0.2)
            let overcast = skyRamp(y, 0.45, 0.6) * (1 - skyRamp(chroma, 0.10, 0.18))
            let sunset = skyRamp(y, 0.35, 0.5) * skyRamp(max(r, b) - g, 0.03, 0.1)
            let foliage = skyRamp(g - max(r, b), 0.02, 0.08)
            out.values[i] = max(blueSky, overcast, sunset) * (1 - foliage)
        }
        return out
    }

    private static func skySmooth(_ y: Plane) -> Plane {
        let r = max(2, max(y.width, y.height) / 256)
        var yy = y
        for i in yy.values.indices { yy.values[i] = y.values[i] * y.values[i] }
        let m = boxMean(y, radius: r), m2 = boxMean(yy, radius: r)
        var out = y
        for i in out.values.indices {
            let sd = max(0, m2.values[i] - m.values[i] * m.values[i]).squareRoot()
            out.values[i] = 1 - skyRamp(sd, 0.012, 0.04)
        }
        return out
    }

    /// 1 where `p` is over `over`, else 0.
    private static func skyBinary(_ p: Plane, over: Float) -> Plane {
        var out = p
        for i in out.values.indices { out.values[i] = p.values[i] > over ? 1 : 0 }
        return out
    }

    /// The 4-connected components of `on`: each pixel's component (-1 where off), and how many.
    private static func skyComponents(_ on: [Bool], width w: Int, height h: Int) -> (of: [Int32], count: Int) {
        var of = [Int32](repeating: -1, count: on.count)
        var count: Int32 = 0
        var stack: [Int] = []
        for s in on.indices where on[s] && of[s] < 0 {
            of[s] = count; stack.append(s)
            while let i = stack.popLast() {
                let x = i % w
                if x > 0, on[i - 1], of[i - 1] < 0 { of[i - 1] = count; stack.append(i - 1) }
                if x < w - 1, on[i + 1], of[i + 1] < 0 { of[i + 1] = count; stack.append(i + 1) }
                if i >= w, on[i - w], of[i - w] < 0 { of[i - w] = count; stack.append(i - w) }
                if i + w < h * w, on[i + w], of[i + w] < 0 { of[i + w] = count; stack.append(i + w) }
            }
            count += 1
        }
        return (of, Int(count))
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
