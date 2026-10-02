import Foundation

// WP-5. The Curve section's graph (prototype `cPts`, `cSpline`, `curveD`, `cAnch`, `presets`):
// Lumina's three curve values move the points at ¼, ½ and ¾ by value / 200, and the curve is the
// monotone cubic through those and the two ends. No state; the view and the tests go through here.

public enum ToneCurve {
    /// The three settings, dark to light, and where each one's point sits.
    public static let keys = ["cDark", "cMid", "cLight"]
    public static let xs = [0.25, 0.5, 0.75]
    /// The words under the graph (the slider labels are "Dark tones", "Midtones", "Light tones").
    public static let shortLabels = ["Darks", "Mids", "Lights"]
    /// Samples along the curve the view draws (the prototype's 48 segments).
    public static let samples = 48

    public struct Point: Equatable, Sendable {
        public var x: Double, y: Double
        public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    }

    /// The five points of a look's curve: the ends, and the three settings' points.
    public static func points(_ look: Look) -> [Point] {
        var p = [Point(0, 0)]
        for (k, x) in zip(keys, xs) { p.append(Point(x, x + (look[k] ?? 0) / 200)) }
        p.append(Point(1, 1))
        return p
    }

    /// The prototype's monotone cubic (Fritsch–Carlson) through `p`, sorted by x, clamped to 0…1.
    public static func spline(_ p: [Point]) -> (Double) -> Double {
        let n = p.count
        guard n >= 2 else { return { min(1, max(0, $0)) } }
        let xs = p.map(\.x), ys = p.map(\.y)
        var d = [Double](), m = [Double](repeating: 0, count: n)
        for i in 0..<(n - 1) { d.append((ys[i + 1] - ys[i]) / max(1e-6, xs[i + 1] - xs[i])) }
        m[0] = d[0]; m[n - 1] = d[n - 2]
        for i in 1..<(n - 1) { m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2 }
        for i in 0..<(n - 1) {
            if d[i] == 0 { m[i] = 0; m[i + 1] = 0; continue }
            let a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b
            if s > 9 { let t = 3 / s.squareRoot(); m[i] = t * a * d[i]; m[i + 1] = t * b * d[i] }
        }
        return { x in
            guard x.isFinite else { return ys[0] }
            if x <= xs[0] { return ys[0] }
            if x >= xs[n - 1] { return ys[n - 1] }
            var i = 0
            while i < n - 2, x > xs[i + 1] { i += 1 }
            let h = xs[i + 1] - xs[i], t = (x - xs[i]) / h, t2 = t * t, t3 = t2 * t
            let y = (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * m[i + 1]
            return min(1, max(0, y))
        }
    }

    /// The curve at `samples + 1` evenly spaced inputs, 0…1 (what the view draws).
    public static func curve(_ look: Look) -> [Double] {
        let f = spline(points(look))
        return (0...samples).map { f(Double($0) / Double(samples)) }
    }

    /// The three settings that put a curve through `p`'s shape at ¼, ½ and ¾ (prototype `setCurve`).
    public static func values(through p: [Point]) -> Look {
        let f = spline(p)
        var l = Look()
        for (k, x) in zip(keys, xs) {
            let v = (f(x) - x) * 200
            l[k] = EditSetting.byKey[k].map { SliderScale.round($0, v.rounded()) } ?? v.rounded()
        }
        return l
    }

    /// The preset chips (prototype `presets`). "Fade" lifts the ends, which three values can't hold: left out.
    public static let presets: [(name: String, look: Look)] = {
        let shapes: [(String, [Point])] = [
            ("Linear", [Point(0, 0), Point(1, 1)]),
            ("Soft contrast", [Point(0, 0), Point(0.25, 0.21), Point(0.75, 0.79), Point(1, 1)]),
            ("Strong contrast", [Point(0, 0), Point(0.25, 0.16), Point(0.75, 0.85), Point(1, 1)]),
            ("Brighten", [Point(0, 0), Point(0.5, 0.6), Point(1, 1)]),
        ]
        return shapes.map { (name: $0.0, look: ToneCurve.values(through: $0.1)) }
    }()
}
