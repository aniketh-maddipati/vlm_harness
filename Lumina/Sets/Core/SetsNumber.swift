import Foundation

/// Numbers as the page sends them (a script message's `NSNumber`, a `lumina://` query's text),
/// read without trusting them. JavaScript sends `Infinity`, `NaN` and `1e300` as easily as `1`,
/// and `Int(Double)` on any of those stops the app (Q4-hostile F1, F2). Every numeric field of
/// every bridge op and every query number goes through here: a value that is not a number, not
/// finite, or outside the field's stated range comes back nil (the caller's default, the same as
/// a missing field) or, with `clamp`, as the nearest end of the range. A boolean is not a number.
nonisolated enum SetsNumber {
    /// JavaScript's largest exact integer (2^53 − 1): the most a page counter can reach.
    static let maxSafeInteger = 9_007_199_254_740_991

    /// A finite number in `range`. Out of range: nil, or the nearest end with `clamp`.
    static func double(_ v: Any?, in range: ClosedRange<Double>, clamp: Bool = false) -> Double? {
        guard let d = number(v)?.doubleValue, d.isFinite else { return nil }
        if range.contains(d) { return d }
        return clamp ? min(max(d, range.lowerBound), range.upperBound) : nil
    }

    /// A whole number in `range`: an integer, or a double with no fraction (12.0, never 12.5).
    /// With `text`, decimal text too ("12"), which is how a query carries one. Out of range: nil,
    /// or the nearest end with `clamp` (a whole 1e300 clamps to the upper end; NaN and ±Infinity
    /// are never clamped).
    static func int(_ v: Any?, in range: ClosedRange<Int>, clamp: Bool = false, text: Bool = false) -> Int? {
        let i: Int
        if text, let s = v as? String {
            guard let parsed = Int(s) else { return nil }
            i = parsed
        } else if let n = number(v) {
            if let exact = Int(exactly: n) {
                i = exact
            } else {
                // Not an Int: a fraction, a non-finite double, or a whole number beyond Int's range.
                let d = n.doubleValue
                guard clamp, d.isFinite, d == d.rounded() else { return nil }
                return d < 0 ? range.lowerBound : range.upperBound
            }
        } else {
            return nil
        }
        if range.contains(i) { return i }
        return clamp ? min(max(i, range.lowerBound), range.upperBound) : nil
    }

    // MARK: The fields, with their ranges

    /// A byte offset or length inside a RAW, 0 … 2^32 − 1: an ARW is a TIFF, whose offsets and
    /// counts are 32 bits. Anything else is 0, which `SetsIngest` answers "no preview range".
    static func fileRange(_ v: Any?) -> Int { int(v, in: 0...Int(UInt32.max), text: true) ?? 0 }

    /// An EXIF orientation as the tag stores it, a SHORT (0 … 65535; only 3, 6 and 8 turn the
    /// picture). Anything else is 1, upright.
    static func orientation(_ v: Any?) -> Int { int(v, in: 0...65_535, text: true) ?? 1 }

    /// The page's sequence number for a look, 0 … 2^53 − 1. Anything else is 0, "none".
    static func seq(_ v: Any?, text: Bool = false) -> Int { int(v, in: 0...maxSafeInteger, text: text) ?? 0 }

    /// The page's clock for an event (`performance.now()`, ms), 0 … 1e13 (three centuries of
    /// uptime). Anything else is nil: the latency is then measured from the message's arrival.
    static func pageClock(_ v: Any?) -> Double? { double(v, in: 0...1e13) }

    /// The page's device pixel ratio, clamped to 0.5 … 8 (displays are 1, 2 or 3). Not a number: 1.
    static func dpr(_ v: Any?) -> Double { double(v, in: 0.5...8, clamp: true) ?? 1 }

    /// The longest edge the page lays the Edit canvas out at, CSS px: 16,384, more than twice an
    /// 8K display (7,680) and Metal's largest texture edge on Apple silicon.
    static let maxCanvasEdge = 16_384.0

    /// The page's Edit canvas rect in CSS px, from the web view's top-left: x and y within
    /// ± 2 × `maxCanvasEdge`, w and h within 0 … `maxCanvasEdge`. A missing field is 0, as it
    /// always was; a field that is there and is not such a number refuses the whole rect (nil).
    static func canvasRect(_ body: [String: Any]) -> CGRect? {
        var out: [Double] = []
        for (key, range) in [("x", -2 * maxCanvasEdge...2 * maxCanvasEdge), ("y", -2 * maxCanvasEdge...2 * maxCanvasEdge), ("w", 0...maxCanvasEdge), ("h", 0...maxCanvasEdge)] {
            guard let v = body[key] else { out.append(0); continue }
            guard let d = double(v, in: range) else { return nil }
            out.append(d)
        }
        return CGRect(x: out[0], y: out[1], width: out[2], height: out[3])
    }

    /// The page's viewport height in CSS px (`window.innerHeight`) next to the canvas rect, or nil
    /// when it is missing or not a height a display can hold.
    static func viewportHeight(_ v: Any?) -> Double? { v == nil ? nil : double(v, in: 1...maxCanvasEdge) }

    /// The visible region when zoomed, in fractions of the frame (the whole frame is 0, 0, 1, 1;
    /// zoomed out, the canvas shows beyond it): x and y within −64 … 64, w and h within 0
    /// (exclusive) … 64. Anything else: no region.
    static func roi(_ d: Any?) -> (x: Double, y: Double, w: Double, h: Double)? {
        guard let r = d as? [String: Any], let x = double(r["x"], in: -64...64), let y = double(r["y"], in: -64...64),
              let w = double(r["w"], in: 0...64), let h = double(r["h"], in: 0...64), w > 0, h > 0 else { return nil }
        return (x, y, w, h)
    }

    /// A count of photos (in the shoot, decided, kept), 0 … 100,000: the most entries a listing
    /// holds (`SetsIngest.Limits.entries`). Anything else is nil.
    static func count(_ v: Any?) -> Int? { int(v, in: 0...100_000) }

    /// An export's long edge in px, 1 … 65,536 (larger is clamped: a develop never upscales, so
    /// it means full size all the same). Zero, negative or not a number: nil, full size.
    static func exportEdge(_ v: Any?) -> Int? { int(v, in: 1...Int.max, text: true).map { min($0, 65_536) } }

    /// A preview's long edge in px for `lumina://render`, clamped to 64 … 8192. Not a number: 1024.
    static func renderEdge(_ v: Any?) -> Int { int(v, in: 64...8192, clamp: true, text: true) ?? 1024 }

    /// A RAW decoder version (Core Image's are single digits), 1 … 99. Anything else is nil, the default.
    static func decoder(_ v: Any?) -> Int? { int(v, in: 1...99, text: true) }

    /// An `NSNumber` that is a number: a boolean (JavaScript's `true`) is refused.
    private static func number(_ v: Any?) -> NSNumber? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n
    }
}
