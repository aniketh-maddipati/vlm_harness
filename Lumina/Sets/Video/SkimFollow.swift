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

    /// The matte's file name for a clip: the clip's name (without its extension) and " matte.mov", as one plain name.
    static func matteName(clip: String) -> String? {
        let stem = ((clip.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? "") as NSString).deletingPathExtension
        return SkimExport.safeName(stem + " matte.mov", allowed: ["mov"])
    }
}
