import Foundation

/// Per-frame measurements `AutoDevelop` turns into a recipe (restored from before the Phase 6
/// cleanup, `Lumina/Develop/ImageStats.swift`, and moved onto the RAW: BRIDGE-v0.02 §1).
///
/// Everything here is an observation, never a decision: no field depends on the photographer's
/// cull, look or taste. The pixels are the RAW's own, developed small (`AutoDevelopRaw`: 256 px, the
/// default decoder, the rules' rawDevelop with its base match, no look) and read scene-linear in the
/// working space, never the camera's embedded JPEG. The thresholds AutoDevelop was tuned with are
/// display-referred (6/255 and 249/255, a mean anchor of 0.46), as its first version measured the
/// develop through a display colour space: each pixel's linear luminance is therefore encoded with
/// the sRGB transfer curve (clipped at 1) before it is binned, so the same numbers keep their meaning.
nonisolated struct ImageStats: Codable, Hashable, Sendable {
    static let binCount = 32
    /// Clip thresholds in 0…1 (display-encoded), the 6/255 and 249/255 the design specifies.
    static let shadowClipThreshold = 6.0 / 255.0
    static let highlightClipThreshold = 249.0 / 255.0
    /// Rec.709 luminance weights, the rules' default `luma`.
    static let rec709 = [0.2126, 0.7152, 0.0722]

    /// Luminance histogram, `binCount` bins over 0…1 (display-encoded).
    var luminanceBins: [Int]
    /// Fraction of sampled pixels below `shadowClipThreshold`.
    var shadowClipFraction: Double
    /// Fraction of sampled pixels above `highlightClipThreshold`.
    var highlightClipFraction: Double
    /// Mean display-encoded luminance in 0…1.
    var mean: Double
    /// Mean scene-linear luminance (reported, not used by the recipe).
    var linearMean: Double
    /// As-shot white balance from the RAW decoder (Kelvin, tint), when the file carries one.
    var nativeTemperature: Double?
    var nativeTint: Double?

    init(luminanceBins: [Int] = Array(repeating: 0, count: ImageStats.binCount), shadowClipFraction: Double = 0, highlightClipFraction: Double = 0,
         mean: Double = 0, linearMean: Double = 0, nativeTemperature: Double? = nil, nativeTint: Double? = nil) {
        self.luminanceBins = luminanceBins
        self.shadowClipFraction = shadowClipFraction
        self.highlightClipFraction = highlightClipFraction
        self.mean = mean
        self.linearMean = linearMean
        self.nativeTemperature = nativeTemperature
        self.nativeTint = nativeTint
    }

    var sampleCount: Int { luminanceBins.reduce(0, +) }

    /// The sRGB transfer curve on a linear value, clipped to 0…1.
    static func encoded(_ linear: Double) -> Double {
        let v = min(max(linear, 0), 1)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    /// Measures interleaved scene-linear RGBA floats (`count` = 4 × pixels; alpha ignored).
    /// Pixels with a non-finite channel are skipped. Nil when nothing is left to measure.
    static func measure(linearRGBA px: [Float], luma: [Double] = rec709, nativeTemperature: Double? = nil, nativeTint: Double? = nil) -> ImageStats? {
        let w = luma.count == 3 && luma.allSatisfy({ $0.isFinite && $0 >= 0 }) ? luma : rec709
        var bins = [Int](repeating: 0, count: binCount)
        var low = 0, high = 0, samples = 0
        var sum = 0.0, linearSum = 0.0
        var i = 0
        while i + 2 < px.count {
            let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
            i += 4
            guard r.isFinite, g.isFinite, b.isFinite else { continue }
            let y = max(0, w[0] * r + w[1] * g + w[2] * b)
            let v = encoded(y)
            bins[min(binCount - 1, max(0, Int(v * Double(binCount))))] += 1
            if v < shadowClipThreshold { low += 1 }
            if v > highlightClipThreshold { high += 1 }
            sum += v
            linearSum += y
            samples += 1
        }
        guard samples > 0 else { return nil }
        let n = Double(samples)
        return ImageStats(luminanceBins: bins, shadowClipFraction: Double(low) / n, highlightClipFraction: Double(high) / n,
                          mean: sum / n, linearMean: linearSum / n, nativeTemperature: nativeTemperature, nativeTint: nativeTint)
    }
}

/// The deterministic Auto (restored from before the Phase 6 cleanup, `Lumina/Develop/AutoDevelop.swift`).
/// `lumina.auto(rel)` answers with it (BRIDGE-v0.02 §1): one Auto for the A key, arrival-auto and scene
/// matching, from the RAW.
///
/// Pure function of `ImageStats`: the same stats always produce the same recipe, on any machine, in
/// any session. It never reads cull, taste, selection or wall-clock time, and it never decides
/// anything the photographer can't immediately overwrite by hand.
///
/// The recipe is in the Edit page's slider units: `ev` in stops (−5 … +5, step 0.05), `wb` in Kelvin
/// (2500 … 10000, step 10), `tint` and `hl` / `sh` / `wh` / `bl` / `con` on −100 … 100 (tint on the
/// slider's −150 … +150), whole numbers. Auto preserves the white-balance intent: `wb` and `tint` are
/// the decoder's as-shot pair, together, and absent (as shot) when the decoder has none or it lies
/// outside the slider. Whites and Blacks are set to 0, as the first version did; Contrast is left
/// alone. The first version also set Vibrance +8: the Edit page has no Vibrance slider and the
/// bridge contract no `vib`, so this one does not (it would be a change nobody could see or undo).
nonisolated enum AutoDevelop {
    /// Changes whenever a constant or the measurement changes: the cache key, the fixture file's
    /// stamp, and what `lumina.auto` answers as `version`.
    static let version = "autodevelop-2"

    /// Mid-tone anchor the exposure correction pulls `ImageStats.mean` toward.
    static let meanAnchor = 0.46
    static let exposureGain = 3.0
    static let exposureLimit = 1.0
    static let brighteningLimit = 0.35
    static let highlightHeadroomBoundary = 0.80
    static let highlightPercentile = 0.98
    static let shadowLiftLimit = 20.0
    static let highlightRecoveryLimit = 80.0
    static let exposureStep = 0.05
    /// Below this clip fraction a frame counts as "not actually clipping".
    static let clipSignificance = 0.005
    static let defaultHighlights = 0.0
    static let defaultShadows = 0.0

    /// The Edit page's slider ranges (`Lumina Edit v21.dc.html`, `SL`).
    static let evRange = -5.0...5.0
    static let kelvinRange = 2500.0...10000.0
    static let kelvinStep = 10.0
    static let tintRange = -150.0...150.0
    static let toneRange = -100.0...100.0

    /// What `lumina.auto` hands the page, in its slider units.
    struct Recipe: Equatable, Sendable {
        var ev: Double
        var wb: Double?
        var tint: Double?
        var hl: Double
        var sh: Double
        var wh: Double = 0
        var bl: Double = 0

        /// `{ev, wb?, tint?, hl, sh, wh, bl}`: the bridge's `look`.
        var look: [String: Double] {
            var out = ["ev": ev, "hl": hl, "sh": sh, "wh": wh, "bl": bl]
            if let wb, let tint { out["wb"] = wb; out["tint"] = tint }
            return out
        }
    }

    static func recipe(for stats: ImageStats) -> Recipe {
        let wb = whiteBalance(kelvin: stats.nativeTemperature, tint: stats.nativeTint)
        return Recipe(ev: exposure(stats: stats), wb: wb?.kelvin, tint: wb?.tint,
                      hl: highlights(clipFraction: stats.highlightClipFraction), sh: shadows(clipFraction: stats.shadowClipFraction))
    }

    /// Pull the measured mean toward the mid-tone anchor, bounded and quantized so two
    /// near-identical frames in one burst can't land on different values.
    static func exposure(mean: Double) -> Double {
        guard mean.isFinite, (0...1).contains(mean) else { return 0 }
        let raw = (meanAnchor - mean) * exposureGain
        let bounded = min(max(raw, -exposureLimit), brighteningLimit)
        return quantized(bounded)
    }

    /// Histogram headroom is a conservative veto, not a RAW EV estimate: a low mean alone
    /// cannot tell a night scene from underexposure, so brightening needs the 98th percentile
    /// well below white and no significant clipping.
    static func exposure(stats: ImageStats) -> Double {
        let proposed = exposure(mean: stats.mean)
        guard proposed > 0 else { return proposed }
        guard stats.highlightClipFraction.isFinite,
              (0...clipSignificance).contains(stats.highlightClipFraction),
              stats.luminanceBins.count == ImageStats.binCount,
              stats.luminanceBins.allSatisfy({ $0 >= 0 }) else { return 0 }
        let total = stats.luminanceBins.reduce(0.0) { $0 + Double($1) }
        guard total > 0 else { return 0 }
        var cumulative = 0.0
        for (index, count) in stats.luminanceBins.enumerated() {
            cumulative += Double(count)
            if cumulative >= total * highlightPercentile {
                let upperEdge = Double(index + 1) / Double(ImageStats.binCount)
                return upperEdge < highlightHeadroomBoundary ? proposed : 0
            }
        }
        return 0
    }

    /// Recover only genuinely clipped highlights. Whole numbers, −80 … 0.
    static func highlights(clipFraction: Double) -> Double {
        guard clipFraction.isFinite, (0...1).contains(clipFraction), clipFraction > clipSignificance else { return defaultHighlights }
        return -min(highlightRecoveryLimit, (clipFraction * 3000).rounded())
    }

    /// Lift only genuinely crushed shadows. Whole numbers, 0 … 20.
    static func shadows(clipFraction: Double) -> Double {
        guard clipFraction.isFinite, (0...1).contains(clipFraction), clipFraction > clipSignificance else { return defaultShadows }
        return min(shadowLiftLimit, (clipFraction * 1000).rounded())
    }

    /// The as-shot pair in slider units, or nil (as shot) when either is missing, not finite, or
    /// the Kelvin lies outside the slider: clamping it would change the colour, which Auto never does.
    static func whiteBalance(kelvin: Double?, tint: Double?) -> (kelvin: Double, tint: Double)? {
        guard let kelvin, let tint, kelvin.isFinite, tint.isFinite, kelvinRange.contains(kelvin) else { return nil }
        let k = min(max((kelvin / kelvinStep).rounded() * kelvinStep, kelvinRange.lowerBound), kelvinRange.upperBound)
        return (k, min(max(tint.rounded(), tintRange.lowerBound), tintRange.upperBound))
    }

    /// On the 0.05 step, inside the slider, without binary noise (0.35, never 0.35000000000000003).
    static func quantized(_ ev: Double) -> Double {
        let v = (min(max(ev, evRange.lowerBound), evRange.upperBound) / exposureStep).rounded() * exposureStep
        return (v * 100).rounded() / 100 + 0      // + 0: never −0
    }
}
