import Foundation

/// Blue skies and exposure (prototype, behind `Look.skyFeatures`; report
/// docs/masking/eval/2026-10-28-sky-exposure.md). One set of parts: the sky mask (`LookMasks.sky`),
/// the develop's own pixels, and two clip maps measured with Apple's decoder (`LookSkyClip`).
/// Every function here only measures or proposes numbers; what changes a picture is a look
/// string (`ev:`, `mask:sky/ev=…,hl=…,blu=…`), stored where looks are stored. Nothing here
/// touches rules-v1.json. Foundation only: tested on Linux with LookMasks.
nonisolated enum LookSky {
    typealias Plane = LookMasks.Plane

    // MARK: F1 clip diagnosis

    enum Verdict: String, Sendable {
        /// No sky found (the gate said no, or too little sky).
        case noSky = "no-sky"
        /// The sky holds detail in today's render.
        case fine
        /// White in today's render, but the sensor held it: a develop that keeps the range above
        /// white could bring it back (today's decode ends at white, so Highlights alone can't).
        case recoverable
        /// The sensor clipped: nothing to bring back.
        case clippedAtCapture = "clipped-at-capture"
    }

    struct Diagnosis: Equatable, Sendable {
        var verdict: Verdict
        /// Share of the frame that is sky.
        var sky: Double
        /// Share of the sky at display white in today's render (any channel).
        var white: Double
        /// Share of the sky the sensor clipped (any channel); nil when it could not be measured
        /// (an older macOS without the decoder's recovery switch, a non-RAW file).
        var clipped: Double?
        /// Per sensor channel ("r", "g", "b"), when a RAW reader supplied them.
        var channels: [String: Double]?
    }

    /// A sky with at least this share clipped at capture is called clipped; else at least this
    /// share at white is called recoverable. Starting points, set before any labels were seen.
    static let clippedAtLeast = 0.02, whiteAtLeast = 0.02

    /// Area-weighted shares inside the (soft) sky mask. All planes are resampled to the mask's grid.
    static func diagnose(sky: Plane?, white: Plane, clipped: Plane?, channels: [String: Plane]? = nil) -> Diagnosis {
        guard let sky, sky.width > 0, sky.height > 0 else {
            return Diagnosis(verdict: .noSky, sky: 0, white: 0, clipped: nil, channels: nil)
        }
        let total = Double(sky.values.reduce(0, +))
        let skyShare = total / Double(sky.values.count)
        guard total > 0 else { return Diagnosis(verdict: .noSky, sky: 0, white: 0, clipped: nil, channels: nil) }
        func share(_ p: Plane) -> Double {
            let q = resample(p, width: sky.width, height: sky.height)
            var s = 0.0
            for i in 0..<sky.values.count { s += Double(sky.values[i]) * Double(q.values[i]) }
            return s / total
        }
        let w = share(white), c = clipped.map(share)
        let ch = channels?.mapValues(share)
        let verdict: Verdict = (c ?? 0) >= clippedAtLeast ? .clippedAtCapture : w >= whiteAtLeast ? .recoverable : .fine
        return Diagnosis(verdict: verdict, sky: skyShare, white: w, clipped: c, channels: ch)
    }

    /// Box-average resample (or nearest when growing) to `width × height`.
    static func resample(_ p: Plane, width: Int, height: Int) -> Plane {
        if p.width == width && p.height == height { return p }
        var out = Plane(width: width, height: height)
        let sx = Double(p.width) / Double(width), sy = Double(p.height) / Double(height)
        for y in 0..<height {
            let y0 = Int(Double(y) * sy), y1 = max(y0 + 1, min(p.height, Int(Double(y + 1) * sy)))
            for x in 0..<width {
                let x0 = Int(Double(x) * sx), x1 = max(x0 + 1, min(p.width, Int(Double(x + 1) * sx)))
                var s: Float = 0
                for yy in y0..<min(y1, p.height) { for xx in x0..<min(x1, p.width) { s += p.values[yy * p.width + xx] } }
                out.values[y * width + x] = s / Float(max(1, (min(y1, p.height) - y0) * (min(x1, p.width) - x0)))
            }
        }
        return out
    }

    // MARK: F6 capture tip

    /// Text for a sky the sensor clipped, nil otherwise. `stopsOver` is how far exposure would have
    /// had to drop (LookSkyClip.stopsOver); nil when it could not be estimated.
    static func captureTip(_ d: Diagnosis, stopsOver: Double?) -> String? {
        guard d.verdict == .clippedAtCapture, let c = d.clipped else { return nil }
        let pct = Int((c * 100).rounded())
        guard let s = stopsOver, s > 0 else { return "Sky was clipped when shot (\(pct) % of it). Less exposure would have kept it." }
        let half = (s * 2).rounded(.up) / 2
        let n = half == half.rounded() ? String(Int(half)) : String(format: "%.1f", half)
        return "Sky was clipped when shot (\(pct) % of it). About \(n) stop\(half == 1 ? "" : "s") less exposure would have kept it."
    }

    // MARK: F2 highlight-safe auto exposure

    struct Meter: Equatable, Sendable {
        /// Median L* of the metered pixels before the move, and the exposure (stops) that puts it on target.
        var midtone: Double
        var ev: Double
        /// Share of the frame metered (not sky, not white, not black).
        var metered: Double
    }

    /// The midtone L* the meter aims for. Fitted once on the bridal-shower edits (a development
    /// set), never on the held-out mehendi edits; see the report.
    static let targetL = 46.0
    static let evRange = -3.0 ... 3.0

    /// Meters `luma` (linear working-space luma of the look-free develop, row 0 at the top) on
    /// what is not sky and not at white or black, and returns the `ev:` that puts the median L*
    /// of those pixels on `target`. Highlights are not metered, so they are left to the tone
    /// curve's shoulder instead of setting the exposure. The move goes through the exposure
    /// stage's own curve (`LookMath.exposure`), so the answer is what the slider will do.
    static func meter(luma: Plane, sky: Plane?, rules: LookRules, target: Double = targetL) -> Meter? {
        let skyQ = sky.map { resample($0, width: luma.width, height: luma.height) }
        var ys: [Double] = []
        ys.reserveCapacity(luma.values.count)
        for i in 0..<luma.values.count {
            let y = Double(luma.values[i])
            if y >= 0.98 || y <= 0.0005 { continue }
            if let s = skyQ, s.values[i] >= 0.5 { continue }
            ys.append(y)
        }
        guard ys.count >= max(64, luma.values.count / 50) else { return nil }
        ys.sort()
        let w = LookMath.exposureWhite(rules)
        func midtone(_ ev: Double) -> Double {
            let g = LookMath.exposureGain(ev, rules)
            return lstar(LookMath.exposure(ys[ys.count / 2], gain: g, white: w))
        }
        let before = midtone(0)
        var lo = evRange.lowerBound, hi = evRange.upperBound
        if midtone(lo) >= target { hi = lo } else if midtone(hi) <= target { lo = hi }
        for _ in 0..<40 where hi - lo > 1e-4 {
            let m = (lo + hi) / 2
            if midtone(m) < target { lo = m } else { hi = m }
        }
        let ev = ((lo + hi) / 2 * 20).rounded() / 20                 // the slider's 0.05 step
        return Meter(midtone: before, ev: ev, metered: Double(ys.count) / Double(luma.values.count))
    }

    /// CIE L* of a linear luminance (white 1).
    static func lstar(_ y: Double) -> Double {
        let t = max(0, y)
        return t > 216.0 / 24389 ? 116 * cbrt(t) - 16 : t * 24389 / 27
    }

    // MARK: F5 exposure across a set

    /// Each photo's `ev:` so the set's metered midtones meet at the set's median midtone: exposure
    /// only (L*), no colour or white balance. `midtones` are `Meter.midtone`; the answer is computed
    /// with each photo's own meter (`meter(…, target:)`), so pass the median back in as the target.
    static func setTarget(_ midtones: [Double]) -> Double? {
        guard !midtones.isEmpty else { return nil }
        let s = midtones.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
