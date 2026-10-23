import Foundation

/// Following one chosen shape through a clip (Skim ▸ Viewer ▸ Follow) and the matte Final Cut gets from it, the parts
/// that are plain maths: which shape in a frame is the one being followed, what the page may send, and which of the
/// followed frames each frame of the matte is made from. Vision's tracker is `SkimFollower`, the matte's file
/// `SkimMatte`. Foundation only: it runs in the Linux Swift sandbox too.
///
/// A person or an object is followed by its box (Vision's object tracker, the mask lab's `vision-box`, which scored the
/// same as following by shape on the clips run so far), and in each frame the shape Vision finds that overlaps the box
/// most is the shape there. The sky and the background are not things that move: in each frame they are that frame's
/// sky or background.
nonisolated enum SkimFollow {
    typealias Box = LookMasks.Box
    typealias Point = LookMasks.Point
    typealias Kind = LookMasks.Kind

    /// The tracker's own figure (0 … 1) under which it has lost the object; the box then stays where it was last held.
    static let hold = 0.3
    /// The least overlap (intersection over union) between the followed box and a shape found in the same frame for
    /// that shape to be the one followed.
    static let overlap = 0.2
    /// Follows open at once (a newer one lets the oldest go), and how long one is kept without a frame.
    static let open = 4
    static let idle: TimeInterval = 120

    // MARK: The followed shape

    static func iou(_ a: Box, _ b: Box) -> Double {
        let x0 = max(a.x, b.x), y0 = max(a.y, b.y), x1 = min(a.x + a.w, b.x + b.w), y1 = min(a.y + a.h, b.y + b.h)
        let inter = max(0, x1 - x0) * max(0, y1 - y0), uni = a.w * a.h + b.w * b.h - inter
        return uni > 0 ? inter / uni : 0
    }

    /// The kinds followed by a box; the others are found again in each frame.
    static func boxed(_ k: Kind) -> Bool { k != .sky && k != .background }

    /// The shape in `found` that is the one followed: the frame's own sky or background, or for anything else the shape
    /// (never the sky or the background) whose box overlaps `box` most, at least `overlap`. Nil: not in this frame.
    static func match(kind: Kind, box: Box?, in found: [LookMasks.Found]) -> LookMasks.Found? {
        guard boxed(kind) else { return found.first { $0.kind == kind } }
        guard let box else { return nil }
        var best: LookMasks.Found?, bestO = overlap
        for f in found where boxed(f.kind) {
            let o = iou(f.box, box)
            // the same overlap: the shape of the kind chosen (the subject over the person it also is)
            if o > bestO || (o == bestO && best != nil && f.kind == kind && best?.kind != kind) { best = f; bestO = o }
        }
        return best
    }

    /// Vision's boxes run from the bottom left, the page's from the top left; the same flip goes both ways.
    static func flipped(_ b: Box) -> Box { Box(x: b.x, y: 1 - b.y - b.h, w: b.w, h: b.h) }

    /// A start as the page sends it: the kind of the shape chosen and its box, `[x, y, w, h]` in fractions of the
    /// frame from the top left. Nil for anything else, or a box with nothing in it.
    static func start(kind: Any?, box: Any?) -> (kind: Kind, box: Box)? {
        guard let s = kind as? String, let k = Kind(rawValue: s), let b = Self.box(box) else { return nil }
        return (k, b)
    }

    static func box(_ any: Any?) -> Box? {
        guard let a = any as? [Any], a.count == 4 else { return nil }
        let v = a.compactMap { ($0 as? NSNumber)?.doubleValue }
        guard v.count == 4, v.allSatisfy(\.isFinite) else { return nil }
        let x = min(1, max(0, v[0])), y = min(1, max(0, v[1])), w = min(1 - x, max(0, v[2])), h = min(1 - y, max(0, v[3]))
        return w > 0.001 && h > 0.001 ? Box(x: x, y: y, w: w, h: h) : nil
    }

    /// One frame of a follow: where the box is, whether the shape is there, and its outline when it is.
    struct Step: Equatable, Sendable {
        var box: Box?
        var held: Bool
        var shape: LookMasks.Found?

        var json: [String: Any] {
            func r(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
            var o: [String: Any] = ["held": held]
            o["box"] = box.map { [r($0.x), r($0.y), r($0.w), r($0.h)] } ?? NSNull()
            o["shape"] = shape?.dictionary ?? NSNull()
            return o
        }
    }

    // MARK: The matte

    /// The matte's long edge at most: Final Cut scales a mask to the frame, and a feathered edge needs no more.
    static let matteEdge = 1920
    /// Followed frames a matte may be made from (about 40 minutes at the page's 8 a second), and points in one.
    static let maxSamples = 20_000
    static let maxPoints = 4_000
    /// Frames in a matte at most: two hours at 60p.
    static let maxFrames = 432_000

    /// The matte's size for a clip `width × height`: the clip's aspect, at most `matteEdge` on the long edge, even
    /// (H.264 wants even sides).
    static func matteSize(width: Int, height: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0, width <= 16_384, height <= 16_384 else { return nil }
        let s = min(1, Double(matteEdge) / Double(max(width, height)))
        func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
        return (even(Double(width) * s), even(Double(height) * s))
    }

    /// One followed frame: its time in the clip (seconds) and the shape's outline there (empty: not there).
    struct Sample: Equatable, Sendable {
        var t: Double
        var outline: [[Point]]
    }

    /// The page's followed frames, in time order: `[{t, outline: [[[x, y], …], …]}]`. Nil when it is not that, or holds
    /// more than `maxSamples`; a loop with more than `maxPoints` points or a point that is not two finite numbers is
    /// left out of its frame.
    static func samples(_ any: Any?) -> [Sample]? {
        guard let a = any as? [Any], !a.isEmpty, a.count <= maxSamples else { return nil }
        var out: [Sample] = []
        out.reserveCapacity(a.count)
        for e in a {
            guard let d = e as? [String: Any], let t = (d["t"] as? NSNumber)?.doubleValue, t.isFinite, t >= 0 else { return nil }
            var loops: [[Point]] = []
            for l in d["outline"] as? [Any] ?? [] {
                guard let pts = l as? [Any], pts.count >= 3, pts.count <= maxPoints else { continue }
                let loop = pts.compactMap { p -> Point? in
                    guard let xy = p as? [Any], xy.count == 2, let x = (xy[0] as? NSNumber)?.doubleValue, let y = (xy[1] as? NSNumber)?.doubleValue,
                          x.isFinite, y.isFinite else { return nil }
                    return Point(x: x, y: y)
                }
                if loop.count == pts.count { loops.append(loop) }
            }
            out.append(Sample(t: t, outline: loops))
        }
        return out.sorted { $0.t < $1.t }
    }

    /// The followed frames a matte frame at `t` is made from: the one before and the one after, and how much of the
    /// later one (0 … 1). Before the first or after the last, that one alone.
    static func around(_ t: Double, in s: [Sample]) -> (before: Int, after: Int, weight: Double)? {
        guard !s.isEmpty else { return nil }
        if t <= s[0].t { return (0, 0, 0) }
        if t >= s[s.count - 1].t { return (s.count - 1, s.count - 1, 0) }
        var lo = 0, hi = s.count - 1                      // s[lo].t < t < s[hi].t
        while hi - lo > 1 { let m = (lo + hi) / 2; if s[m].t <= t { lo = m } else { hi = m } }
        let span = s[hi].t - s[lo].t
        return (lo, hi, span > 0 ? (t - s[lo].t) / span : 0)
    }

    /// A frame length as the page sends it, `[n, d]` (n/d seconds, Final Cut's `frameDuration`): 1 to 240 frames a second.
    static func frameLength(_ any: Any?) -> (n: Int, d: Int)? {
        guard let a = any as? [Any], a.count == 2, let n = (a[0] as? NSNumber)?.intValue, let d = (a[1] as? NSNumber)?.intValue,
              n > 0, d > 0, d <= 1_000_000, Double(d) / Double(n) >= 1, Double(d) / Double(n) <= 240 else { return nil }
        return (n, d)
    }

    /// The matte frame `k` (of frames `frameLength` long) is made from: the followed frames around its middle, mixed by
    /// time (`around`). When the follow has every frame (the Mac's own track, `SkimTracker`), the two around a frame are
    /// at most a frame and a half apart, and the frame is the one followed frame nearest its start alone: mixing two
    /// outlines a frame apart is what draws a fast arm as two faint ones.
    static func matteFrame(_ k: Int, frameLength fl: (n: Int, d: Int), in s: [Sample]) -> (before: Int, after: Int, weight: Double)? {
        let step = Double(fl.n) / Double(fl.d)
        guard let a = around((Double(k) + 0.5) * step, in: s) else { return nil }
        guard a.before != a.after, s[a.after].t - s[a.before].t <= step * 1.5 else { return a }
        let t = Double(k) * step + step * 0.25
        let i = abs(s[a.before].t - t) <= abs(s[a.after].t - t) ? a.before : a.after
        return (i, i, 0)
    }

    // MARK: The edge (scroll and ⇧-scroll on the chosen shape)

    /// How far the page may grow or shrink the edge, and soften it, as a fraction of the frame's long edge.
    static let maxGrow = 0.05
    static let maxSoft = 0.05

    /// The edge as the page sends it: grow (negative shrinks) and soften, fractions of the long edge, cut to their
    /// limits. Missing or not a number: 0.
    static func edge(grow: Any?, soft: Any?) -> (grow: Double, soft: Double) {
        func v(_ a: Any?) -> Double { (a as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite ? $0 : nil } ?? 0 }
        return (min(maxGrow, max(-maxGrow, v(grow))), min(maxSoft, max(0, v(soft))))
    }

    /// A mask with its edge moved out by `grow` pixels (in by a negative one) and softened over `soft` pixels: a
    /// tent blur as wide as the move, cut near its foot (so the edge moves about that far, a little rounder at corners),
    /// then a tent blur as wide as the softening.
    static func edged(_ p: LookMasks.Plane, grow: Int, soft: Int) -> LookMasks.Plane {
        var m = p
        if grow != 0 {
            let r = max(1, (abs(grow) + 1) / 2), b = LookMasks.boxMean(LookMasks.boxMean(p, radius: r), radius: r)
            let cut: Float = grow > 0 ? 0.04 : 0.96
            for i in m.values.indices { m.values[i] = b.values[i] > cut ? 1 : 0 }
            if grow < 0 { for i in m.values.indices where p.values[i] < m.values[i] { m.values[i] = p.values[i] } }
        }
        if soft > 0 { let r = max(1, (soft + 1) / 2); m = LookMasks.boxMean(LookMasks.boxMean(m, radius: r), radius: r) }
        return m
    }

    // MARK: The Mac's own track (SkimTracker)

    /// The long edge of the frames the Mac reads a clip at to follow a shape: the mask lab's proxy, where Vision's
    /// tracker and its instance masks were measured. The matte is drawn from the outline at its own size.
    static let proxyEdge = 720
    /// Tracks open at once (a newer one lets the oldest go), how long a finished one is kept for the page and its matte,
    /// and frames in one at most (two hours at 60p, as the matte).
    static let tracks = 4
    static let kept: TimeInterval = 30 * 60
    static let maxTracked = maxFrames
    /// Followed frames handed to the page in one answer.
    static let page = 240

    /// The size a clip `width × height` is read at: its aspect, at most `proxyEdge` on the long edge, never larger
    /// than the clip, even sides.
    static func proxySize(width: Int, height: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0, width <= 16_384, height <= 16_384 else { return nil }
        let s = min(1, Double(proxyEdge) / Double(max(width, height)))
        func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
        return (even(Double(width) * s), even(Double(height) * s))
    }

    /// The stretches the clip is read in going back from `t0` to its start (a reader only goes forward): `chunk`
    /// seconds each, latest first, each from its start to its end. Empty when `t0` is the start.
    static func backChunks(from t0: Double, chunk: Double) -> [(from: Double, to: Double)] {
        guard t0 > 0, chunk > 0, t0.isFinite else { return [] }
        var out: [(from: Double, to: Double)] = [], end = t0
        while end > 1e-9, out.count < 100_000 {
            let start = max(0, end - chunk)
            out.append((start, end)); end = start
        }
        return out
    }

    /// How sure a followed frame is, for the strip under the scrub bar: sure, shaky (worth a look), or lost.
    enum Sure: String, Sendable { case sure, shaky, lost }

    /// The tracker's figure under which a frame it held is only shaky.
    static let steady = 0.5
    /// The shape's area from one followed frame to the next, as a ratio, past which the frame is shaky (a limb lost or
    /// a second person taken in).
    static let jump = 1.35

    /// A followed frame's sureness: lost when the shape is not found and the tracker did not hold it; shaky when only
    /// the tracker held it, when the shape was found again after being lost (`refound`), when the tracker was unsure,
    /// or when the shape's area jumped; sure otherwise. The sky and the background have no tracker (`tracker` nil).
    static func sureness(tracker: Double?, found: Bool, area: Double?, last: Double?, refound: Bool) -> Sure {
        if !found { return (tracker ?? 0) >= hold ? .shaky : .lost }
        if refound { return .shaky }
        if let tracker, tracker < steady { return .shaky }
        if let area, let last, area > 0, last > 0, max(area / last, last / area) > jump { return .shaky }
        return .sure
    }

    /// One stretch of the strip: from the first followed frame's time to the last's, all equally sure.
    struct Run: Equatable, Sendable {
        var t0: Double, t1: Double, sure: Sure
        var json: [String: Any] { ["t0": (t0 * 1000).rounded() / 1000, "t1": (t1 * 1000).rounded() / 1000, "sure": sure.rawValue] }
    }

    /// The strip: followed frames in time order, consecutive equal ones as one stretch.
    static func strip(_ frames: [(t: Double, sure: Sure)]) -> [Run] {
        var out: [Run] = []
        for f in frames.sorted(by: { $0.t < $1.t }) {
            if let l = out.last, l.sure == f.sure { out[out.count - 1].t1 = f.t } else { out.append(Run(t0: f.t, t1: f.t, sure: f.sure)) }
        }
        return out
    }

    /// The stretch a fix at `t` re-tracks (the user chose the shape again on that frame): from the end of the last sure
    /// stretch before `t` to the start of the first sure one after it, within the clip (0 … `length`).
    static func fixSpan(at t: Double, strip: [Run], length: Double) -> (from: Double, to: Double) {
        let from = strip.filter { $0.sure == .sure && $0.t1 < t }.map(\.t1).max() ?? 0
        let to = strip.filter { $0.sure == .sure && $0.t0 > t }.map(\.t0).min() ?? length
        return (max(0, min(from, t)), max(t, min(to, length)))
    }

    /// A track with a fixed stretch in place: the frames of `base` outside `from … to`, and those of `patch` inside it,
    /// in time order.
    static func merged(_ base: [Tracked], patch: [Tracked], from: Double, to: Double) -> [Tracked] {
        let inside = { (f: Tracked) in f.t >= from - 1e-6 && f.t <= to + 1e-6 }
        return (base.filter { !inside($0) } + patch.filter(inside)).sorted { $0.t < $1.t }
    }

    /// The largest distance between the chosen shape's feature print and a shape's in a later frame for that shape to be
    /// it, found again after it was lost (behind a pillar, out of the frame). To set from the mask lab's V2 run.
    static let refind = 0.6
    /// Frames lost before the shapes in a frame are compared to the chosen one (each comparison is a feature print).
    static let lostFor = 3

    /// The kinds a shape lost as `kind` may be found again as: a person as a person or the subject, an object as an
    /// object or the subject, the subject as any of them.
    static func refindable(_ kind: Kind, as other: Kind) -> Bool {
        switch kind {
        case .person: return other == .person || other == .subject
        case .object: return other == .object || other == .subject
        case .subject: return boxed(other)
        case .sky, .background: return false
        }
    }

    /// The shape found again: of the shapes in a frame and their feature-print distance to the chosen one, the nearest
    /// of a kind it may be (`refindable`), under `refind`. Nil: none is it.
    static func refound(_ kind: Kind, among c: [(id: String, kind: Kind, distance: Double)]) -> String? {
        c.filter { refindable(kind, as: $0.kind) && $0.distance.isFinite && $0.distance <= refind }.min { $0.distance < $1.distance }?.id
    }

    /// One frame of the Mac's track as the page gets it: its time, the box, whether it is held, how sure, and the outline.
    struct Tracked: Equatable, Sendable {
        var t: Double
        var step: Step
        var sure: Sure
        var area: Double? { step.shape?.area }

        var json: [String: Any] {
            var o = step.json
            o["t"] = (t * 10_000).rounded() / 10_000
            o["sure"] = sure.rawValue
            o["outline"] = step.shape.map { s in s.outline.map { l in l.map { [($0.x * 10_000).rounded() / 10_000, ($0.y * 10_000).rounded() / 10_000] } } } ?? NSNull()
            o.removeValue(forKey: "shape")
            return o
        }
    }

    /// A track's id as the page sends it: 1 to 64 characters.
    static func trackID(_ any: Any?) -> String? {
        guard let s = any as? String, !s.isEmpty, s.utf8.count <= 64 else { return nil }
        return s
    }

    /// A time as the page sends it: seconds into the clip, at least 0.
    static func time(_ any: Any?) -> Double? {
        guard let v = (any as? NSNumber)?.doubleValue, v.isFinite, v >= 0, v < 1e7 else { return nil }
        return v
    }

    /// The matte's file name for a clip: the clip's name (without its extension) and " matte.mov", as one plain name.
    static func matteName(clip: String) -> String? {
        let stem = ((clip.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? "") as NSString).deletingPathExtension
        return SkimExport.safeName(stem + " matte.mov", allowed: ["mov"])
    }
}
