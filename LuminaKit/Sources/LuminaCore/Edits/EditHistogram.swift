import Foundation

// WP-5. What the histogram above the tools row draws (prototype `data-lumina="histogram"`): a
// luma shape of `points` heights and the two clipping markers. Measured by the image provider
// when it can (`HistogramProviding`); otherwise the prototype's estimate from the look.

public struct EditHistogram: Equatable, Sendable {
    /// Heights across the range, as the prototype's path (44 points on a 176 × 52 box).
    public static let points = 44
    /// More than this share of the pixels at pure black (white) lights the marker.
    public static let clipShare: Float = 0.005

    /// `points` heights, 0…1, the tallest 1.
    public var heights: [Double]
    public var shadowsClipping: Bool
    public var highlightsClipping: Bool
    /// From the picture (true) or the prototype's estimate (false).
    public var measured: Bool
    /// The photo and look it was measured for.
    public internal(set) var photo: String?
    public internal(set) var look: Look?

    public init(heights: [Double], shadowsClipping: Bool, highlightsClipping: Bool, measured: Bool) {
        self.heights = heights; self.shadowsClipping = shadowsClipping; self.highlightsClipping = highlightsClipping; self.measured = measured
    }

    /// From measured bins (shares of the pixels per level, black first). Nil for no pixels.
    public init?(bins: [Float]) {
        let n = bins.count
        let total = bins.reduce(0) { $0 + ($1.isFinite ? max(0, $1) : 0) }
        guard n >= 2, total > 0 else { return nil }
        let share = bins.map { ($0.isFinite ? max(0, $0) : 0) / total }
        // Each point averages the levels around it, so 256 levels read as a smooth shape.
        let N = Self.points
        var h = [Double](repeating: 0, count: N)
        for i in 0..<N {
            let c = Double(i) / Double(N - 1) * Double(n - 1), half = Double(n) / Double(N)
            let lo = max(0, Int((c - half).rounded(.down))), hi = min(n - 1, Int((c + half).rounded(.up)))
            var sum: Float = 0
            for j in lo...hi { sum += share[j] }
            h[i] = Double(sum) / Double(hi - lo + 1)
        }
        // A spike of clipped pixels at either end would flatten the rest: the scale ignores the
        // two end points (the markers say it), and they are capped at the top.
        let inner = h.count > 2 ? h[1..<(h.count - 1)].max() ?? 0 : h.max() ?? 0
        let top = inner > 0 ? inner : (h.max() ?? 1)
        self.init(heights: h.map { min(1, $0 / max(top, 1e-12)) },
                  shadowsClipping: share[0] > Self.clipShare, highlightsClipping: share[n - 1] > Self.clipShare, measured: true)
    }

    /// The prototype's histogram (`hist.d`, `loClip`, `hiClip`): a shape from the photo's
    /// brightness that exposure, contrast, highlights and shadows move, for a provider that can't measure.
    public static func estimate(_ look: Look, brightness h: Double) -> EditHistogram {
        func v(_ k: String) -> Double { look[k] ?? EditSetting.byKey[k]?.def ?? 0 }
        let ev = v("ev"), hl = v("hl"), sh = v("sh"), con = v("con")
        func g(_ x: Double, _ m: Double, _ sd: Double) -> Double { exp(-pow((x - m) / sd, 2)) }
        let m = max(0.05, min(0.95, 0.32 + h * 0.28 + ev * 0.11)), spread = 0.17 * (1 - con / 250)
        let ys = (0..<points).map { i -> Double in
            let x = Double(i) / Double(points - 1)
            return g(x, m, spread) + 0.45 * g(x, min(0.97, m + 0.3 - hl * 0.0012), 0.08) + 0.35 * g(x, max(0.03, 0.12 + sh * 0.0016), 0.07)
        }
        let top = ys.max() ?? 1
        return EditHistogram(heights: ys.map { top > 0 ? $0 / top : 0 },
                             shadowsClipping: ev < -1.2 || sh < -50 || (con > 50 && ev < -0.5),
                             highlightsClipping: ev > 1.1 || hl > 60 || (con > 50 && ev > 0.5), measured: false)
    }
}
