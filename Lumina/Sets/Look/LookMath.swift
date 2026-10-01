import Foundation

/// The stage maths, once, in scalar form. `LookKernels` (Metal, on the GPU) and
/// `Tools/parity/lookmath.py` (numpy, for fitting) repeat these formulas line for line, and the
/// tests hold them to it: `LookPipelineTests` renders flat patches through the real graph and
/// compares with `flat(_:)` here, and `lumina-render ramp` dumps the same numbers for the Python
/// mirror. Everything works on the linear working space (`LookRules.workingSpace`), with the
/// tone-shaped stages going through `perceptual(_:)` = x^(1/gamma).
///
/// Structure ideas taken (as ideas, no code) from the references the roadmap allows: the
/// base/detail split for highlights and shadows and the local-contrast form of clarity follow
/// how darktable's and RapidRAW's tone modules are organised; the two-sided power curve for
/// contrast is a simplification of the sigmoid family those modules use.
nonisolated enum LookMath {
    struct RGB: Equatable, Sendable {
        var r: Double, g: Double, b: Double
        static func gray(_ v: Double) -> RGB { RGB(r: v, g: v, b: v) }
        /// Grey within `tolerance` (absolute below 1, relative above): the Oklab matrices are
        /// exact to about 1e-4, half-float intermediates on the GPU to about 1e-3.
        func isNeutral(tolerance: Double = 1e-3) -> Bool {
            let m = max(1, abs(r), abs(g), abs(b))
            return abs(r - g) <= tolerance * m && abs(g - b) <= tolerance * m
        }
        var isNeutral: Bool { isNeutral() }
    }

    static func luma(_ c: RGB, _ rules: LookRules) -> Double {
        rules.luma[0] * c.r + rules.luma[1] * c.g + rules.luma[2] * c.b
    }

    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        guard e1 > e0 else { return x >= e1 ? 1 : 0 }
        let t = min(1, max(0, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    /// Perceptual encoding of a linear value: negatives clamp to 0.
    static func perceptual(_ x: Double, _ rules: LookRules) -> Double { pow(max(0, x), 1 / rules.perceptualGamma) }
    static func linear(_ p: Double, _ rules: LookRules) -> Double { pow(max(0, p), rules.perceptualGamma) }

    // MARK: rawDevelop: the base rendering

    /// The decoder's default rendering brought to Lightroom's (Adobe Color), fitted on base
    /// exports: a midtone curve on luma in perceptual space (hue kept), then a colour mix whose
    /// rows sum to 1, so a grey stays the same grey. Coefficients in `rawDevelop`: `baseLift`,
    /// `baseS` (the curve) and `baseRG`, `baseRB`, `baseGR`, `baseGB`, `baseBR`, `baseBG` (the
    /// off-diagonal mix; the diagonal is what makes each row 1). Last, colour fades toward the
    /// pixel's own luma near white (`baseHiDesat` above perceptual `baseHiFrom`) and in the deepest
    /// shadows (`baseLoDesat` below `baseLoBelow`), as Lightroom's rendering does; the luma itself
    /// does not move. All 0 is the identity.
    struct BaseMatch: Equatable, Sendable {
        var lift = 0.0, s = 0.0
        var rg = 0.0, rb = 0.0, gr = 0.0, gb = 0.0, br = 0.0, bg = 0.0
        var hiDesat = 0.0, hiFrom = 0.9, loDesat = 0.0, loBelow = 0.2
        init() {}
        init(_ rules: LookRules) {
            let k = { (n: String) in rules.k("rawDevelop", n, 0) }
            lift = k("baseLift"); s = k("baseS")
            rg = k("baseRG"); rb = k("baseRB"); gr = k("baseGR"); gb = k("baseGB"); br = k("baseBR"); bg = k("baseBG")
            hiDesat = k("baseHiDesat"); hiFrom = rules.k("rawDevelop", "baseHiFrom", 0.9)
            loDesat = k("baseLoDesat"); loBelow = rules.k("rawDevelop", "baseLoBelow", 0.2)
        }

        /// How much of a pixel's colour is kept at perceptual luma `p` (1 = all of it).
        func chromaKept(_ p: Double) -> Double {
            let pc = min(1, max(0, p))
            let hi = min(1, max(0, (pc - hiFrom) / max(1e-3, 1 - hiFrom))), lo = min(1, max(0, (loBelow - pc) / max(1e-3, loBelow)))
            return min(1, max(0, 1 - hiDesat * hi * hi - loDesat * lo * lo))
        }
        var isIdentity: Bool { lift == 0 && s == 0 && rg == 0 && rb == 0 && gr == 0 && gb == 0 && br == 0 && bg == 0 && hiDesat == 0 && loDesat == 0 }

        /// Rows of the mix: out.r = rows[0] · (r, g, b), …
        var rows: [[Double]] { [[1 - rg - rb, rg, rb], [gr, 1 - gr - gb, gb], [br, bg, 1 - br - bg]] }
    }

    /// The base curve on one luma value (linear in, linear out): identity at 0 and from 1 up.
    static func baseCurve(_ y: Double, _ m: BaseMatch, _ rules: LookRules) -> Double {
        let p = perceptual(y, rules), pc = min(1, max(0, p))
        return linear(p + m.lift * p * (1 - pc) + m.s * p * (1 - pc) * (pc - 0.5), rules)
    }

    static func baseMatch(_ c: RGB, _ m: BaseMatch, _ rules: LookRules) -> RGB {
        guard !m.isIdentity else { return c }
        let y = luma(c, rules)
        let g = y > 1e-6 ? baseCurve(y, m, rules) / y : 1
        let t = RGB(r: c.r * g, g: c.g * g, b: c.b * g), w = m.rows
        let mixed = RGB(r: w[0][0] * t.r + w[0][1] * t.g + w[0][2] * t.b,
                        g: w[1][0] * t.r + w[1][1] * t.g + w[1][2] * t.b,
                        b: w[2][0] * t.r + w[2][1] * t.g + w[2][2] * t.b)
        guard m.hiDesat != 0 || m.loDesat != 0 else { return mixed }
        let ym = luma(mixed, rules), keep = m.chromaKept(perceptual(ym, rules))
        return RGB(r: ym + (mixed.r - ym) * keep, g: ym + (mixed.g - ym) * keep, b: ym + (mixed.b - ym) * keep)
    }

    // MARK: exposure

    /// Lightroom's Exposure is a gain on the scene, before its film-like tone curve; this stage
    /// runs after the decoder's. For a sigmoid tone curve y = xᶜ / (xᶜ + sᶜ) a scene gain g becomes
    /// y′ = G·y / (1 + (G − 1)·y) with G = gᶜ on the toned value, whatever s is: shadows and
    /// midtones move c stops per unit, highlights roll off toward `white` (and, per channel, lose
    /// saturation as they do). `stopsPerUnit` is c; measured on Lightroom's sweep it is ≈ 1.75.
    static func exposureGain(_ ev: Double, _ rules: LookRules) -> Double {
        exp2(ev * rules.k("exposure", "stopsPerUnit", 1))
    }

    /// One channel through the exposure stage: `gain` from `exposureGain`, `white` the value the
    /// roll-off approaches. Above `white` (the decoder's headroom) and below 0 it continues along
    /// its tangent, so it stays monotonic and is the identity at gain 1.
    static func exposure(_ x: Double, gain g: Double, white w: Double) -> Double {
        if x <= 0 { return x * g }
        if x >= w { return w + (x - w) / g }
        let t = x / w
        return w * g * t / (1 + (g - 1) * t)
    }

    static func exposureWhite(_ rules: LookRules) -> Double { max(0.05, rules.k("exposure", "white", 1)) }

    // MARK: whiteBalance

    /// Per-channel multipliers taking the as-shot balance to `target`. Identity when `target` is
    /// nil. Higher Kelvin in the look = the scene was bluer = warm the render (Lightroom's sign).
    static func whiteBalanceGains(_ target: Look.WhiteBalance?, asShot: Look.WhiteBalance, _ rules: LookRules) -> RGB {
        guard let target else { return .gray(1) }
        let dM = 1e6 / max(1000, asShot.kelvin) - 1e6 / max(1000, target.kelvin)     // mired, + = warmer
        let dT = target.tint - asShot.tint
        // Temperature moves red and blue against each other and leaves green (as Lightroom does);
        // tint moves green one way and red and blue the other, each by its own amount.
        var g = RGB(r: exp2(dM * rules.k("whiteBalance", "redPerMired", 0.0025) + dT * rules.k("whiteBalance", "redPerTint", 0)),
                    g: exp2(-dT * rules.k("whiteBalance", "greenPerTint", 0.004)),
                    b: exp2(-dM * rules.k("whiteBalance", "bluePerMired", 0.0025) + dT * rules.k("whiteBalance", "bluePerTint", 0)))
        if rules.k("whiteBalance", "preserveLuma", 1) >= 0.5 {
            let y = luma(g, rules)
            g = RGB(r: g.r / y, g: g.g / y, b: g.b / y)
        }
        return g
    }

    static func whiteBalanceWhite(_ rules: LookRules) -> Double { max(0.05, rules.k("whiteBalance", "white", 1)) }

    // MARK: whitesBlacks (perceptual, per channel)

    static func whitesBlacks(_ p: Double, whites: Double, blacks: Double, _ rules: LookRules) -> Double {
        let bAmt = -blacks * rules.k("whitesBlacks", "blacksPerUnit", 0.002)
        let wAmt = whites * rules.k("whitesBlacks", "whitesPerUnit", 0.003)
        let pc = min(1, max(0, p))
        var q = p - bAmt * pow(1 - pc, rules.k("whitesBlacks", "blacksPower", 2))
        q += wAmt * pow(pc, rules.k("whitesBlacks", "whitesPower", 2))
        return max(0, q)
    }

    // MARK: tone (highlights / shadows on a base)

    /// Multiplicative gain from the base's perceptual luma.
    static func toneGain(baseP: Double, highlights: Double, shadows: Double, _ rules: LookRules) -> Double {
        let s = shadows * rules.k("tone", "shadowsStopsPerUnit", 0.01)
            * (1 - smoothstep(rules.k("tone", "shadowsLo", 0), rules.k("tone", "shadowsHi", 0.6), baseP))
        let h = highlights * rules.k("tone", "highlightsStopsPerUnit", 0.01)
            * smoothstep(rules.k("tone", "highlightsLo", 0.4), rules.k("tone", "highlightsHi", 1), baseP)
        return exp2(s + h)
    }

    /// Detail re-applied with a gain: (luma / base)^(detailGain − 1). 1 on a flat patch.
    static func toneDetail(luma y: Double, base: Double, _ rules: LookRules) -> Double {
        let d = rules.k("tone", "detailGain", 1)
        guard abs(d - 1) > 1e-9 else { return 1 }
        return pow(max(1e-6, y) / max(1e-6, base), d - 1)
    }

    // MARK: contrast (perceptual)

    static func contrastCurve(_ p: Double, contrast: Double, _ rules: LookRules) -> Double {
        let m = min(0.95, max(0.05, rules.k("contrast", "midpoint", 0.46)))
        let a = exp2(contrast * rules.k("contrast", "slopePerUnit", 0.006))
        if p <= 0 { return 0 }
        if p >= 1 { return p }                                   // above white: untouched, clipped later
        return p < m ? m * pow(p / m, a) : 1 - (1 - m) * pow((1 - p) / (1 - m), a)
    }

    /// The stage on a pixel: per channel and on luma, mixed by `lumaMix` (0 = per channel).
    static func contrast(_ c: RGB, contrast amount: Double, _ rules: LookRules) -> RGB {
        guard amount != 0 else { return c }
        let mix = min(1, max(0, rules.k("contrast", "lumaMix", 0.5)))
        let per = RGB(r: linear(contrastCurve(perceptual(c.r, rules), contrast: amount, rules), rules),
                      g: linear(contrastCurve(perceptual(c.g, rules), contrast: amount, rules), rules),
                      b: linear(contrastCurve(perceptual(c.b, rules), contrast: amount, rules), rules))
        let y = luma(c, rules)
        let ratio = y > 1e-9 ? linear(contrastCurve(perceptual(y, rules), contrast: amount, rules), rules) / y : 1
        let byLuma = RGB(r: c.r * ratio, g: c.g * ratio, b: c.b * ratio)
        return RGB(r: per.r + (byLuma.r - per.r) * mix, g: per.g + (byLuma.g - per.g) * mix, b: per.b + (byLuma.b - per.b) * mix)
    }

    // MARK: colour (Oklab chroma)

    /// Sign-preserving cube root, as the Metal kernel writes it (Metal has no cbrt).
    static func cbrtSigned(_ x: Double) -> Double { x < 0 ? -pow(-x, 1.0 / 3) : pow(x, 1.0 / 3) }

    /// Oklab (Björn Ottosson's public-domain matrices) from linear sRGB primaries.
    static func toOklab(_ c: RGB) -> (L: Double, a: Double, b: Double) {
        let l = cbrtSigned(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b)
        let m = cbrtSigned(0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b)
        let s = cbrtSigned(0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func fromOklab(_ L: Double, _ a: Double, _ b: Double) -> RGB {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return RGB(r: 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                   g: -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                   b: -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    static func chromaFactor(chroma C: Double, hueDegrees h: Double, vibrance: Double, saturation: Double, bw: Bool, _ rules: LookRules) -> Double {
        if bw { return 0 }
        let sat = max(0, 1 + saturation * rules.k("colour", "saturationPerUnit", 0.01))
        let cmax = max(1e-6, rules.k("colour", "vibranceChromaMax", 0.25))
        var dh = abs(h - rules.k("colour", "skinHue", 60)).truncatingRemainder(dividingBy: 360)
        if dh > 180 { dh = 360 - dh }
        let skin = exp(-pow(dh / max(1e-6, rules.k("colour", "skinWidth", 25)), 2))
        let protect = vibrance > 0 ? 1 - rules.k("colour", "skinProtect", 0.7) * skin : 1
        let vib = max(0, 1 + vibrance * rules.k("colour", "vibrancePerUnit", 0.01) * (1 - min(1, C / cmax)) * protect)
        return sat * vib
    }

    static func colour(_ c: RGB, vibrance: Double, saturation: Double, bw: Bool, _ rules: LookRules) -> RGB {
        guard vibrance != 0 || saturation != 0 || bw else { return c }
        let lab = toOklab(c)
        let C = hypot(lab.a, lab.b)
        guard C > 1e-9 else { return c }
        var h = atan2(lab.b, lab.a) * 180 / .pi
        if h < 0 { h += 360 }
        let f = chromaFactor(chroma: C, hueDegrees: h, vibrance: vibrance, saturation: saturation, bw: bw, rules)
        let out = fromOklab(lab.L, lab.a * f, lab.b * f)
        return RGB(r: max(0, out.r), g: max(0, out.g), b: max(0, out.b))
    }

    // MARK: clarity (perceptual luma on a base)

    static func clarity(_ q: Double, base: Double, clarity amount: Double, _ rules: LookRules) -> Double {
        let mid = 1 - pow(abs(2 * min(1, max(0, q)) - 1), rules.k("clarity", "midtonePower", 2))
        return max(0, q + amount * rules.k("clarity", "amountPerUnit", 0.01) * (q - base) * mid)
    }

    // MARK: sharpen (perceptual luma on a blur)

    static func sharpen(_ q: Double, blur: Double, amount: Double, _ rules: LookRules) -> Double {
        let hp = q - blur
        let t = max(1e-6, rules.k("sharpen", "threshold", 0.01))
        let mask = smoothstep(t, 2 * t, abs(hp))
        return max(0, q + amount * rules.k("sharpen", "amountPerUnit", 0.01) * hp * mask)
    }

    /// The blur radius in pixels at `longEdge`: `radiusPx` is stated at `refPx` (the parity size).
    static func sharpenRadius(longEdge: Double, _ rules: LookRules) -> Double {
        rules.k("sharpen", "radiusPx", 1) * longEdge / max(1, rules.k("sharpen", "refPx", 2048))
    }

    // MARK: vignette

    /// `r`: distance from the centre over the half diagonal (0 centre, 1 corners).
    static func vignetteGain(r: Double, vignette: Double, _ rules: LookRules) -> Double {
        let m = rules.k("vignette", "midpoint", 0.5), f = rules.k("vignette", "feather", 0.5)
        return exp2(vignette * rules.k("vignette", "stopsPerUnit", 0.02) * smoothstep(m - f / 2, m + f / 2, r))
    }

    // MARK: the whole chain on a flat patch

    /// Every stage on one colour, where blur(x) == x (a flat patch) and the pixel is at the frame's
    /// centre (vignette gain 1 unless `r` says otherwise). This is what the pipeline tests and the
    /// Python mirror compare against.
    static func flat(_ input: RGB, look: Look, asShot: Look.WhiteBalance, rules: LookRules, vignetteR r: Double = 0) -> RGB {
        var c = input
        for stage in rules.lookStages {
            switch stage {
            case "exposure":
                guard look.ev != 0 else { continue }
                let g = exposureGain(look.ev, rules), w = exposureWhite(rules)
                c = RGB(r: exposure(c.r, gain: g, white: w), g: exposure(c.g, gain: g, white: w), b: exposure(c.b, gain: g, white: w))
            case "whiteBalance":
                guard look.wb != nil else { continue }
                // Like exposure, the gains are on the scene: each channel goes through the tone curve,
                // so a cast is full strength in the shadows and fades toward white.
                let g = whiteBalanceGains(look.wb, asShot: asShot, rules), w = whiteBalanceWhite(rules)
                c = RGB(r: exposure(c.r, gain: g.r, white: w), g: exposure(c.g, gain: g.g, white: w), b: exposure(c.b, gain: g.b, white: w))
            case "whitesBlacks":
                guard look.whites != 0 || look.blacks != 0 else { continue }
                c = RGB(r: linear(whitesBlacks(perceptual(c.r, rules), whites: look.whites, blacks: look.blacks, rules), rules),
                        g: linear(whitesBlacks(perceptual(c.g, rules), whites: look.whites, blacks: look.blacks, rules), rules),
                        b: linear(whitesBlacks(perceptual(c.b, rules), whites: look.whites, blacks: look.blacks, rules), rules))
            case "tone":
                guard look.highlights != 0 || look.shadows != 0 else { continue }
                let y = luma(c, rules)
                let g = toneGain(baseP: perceptual(y, rules), highlights: look.highlights, shadows: look.shadows, rules) * toneDetail(luma: y, base: y, rules)
                c = RGB(r: c.r * g, g: c.g * g, b: c.b * g)
            case "contrast":
                c = contrast(c, contrast: look.contrast, rules)
            case "colour":
                c = colour(c, vibrance: look.vibrance, saturation: look.saturation, bw: look.bw, rules)
            case "clarity", "sharpen":
                continue                                          // q − base == 0 on a flat patch
            case "vignette":
                guard look.vignette != 0 else { continue }
                let g = vignetteGain(r: r, vignette: look.vignette, rules)
                c = RGB(r: c.r * g, g: c.g * g, b: c.b * g)
            default:
                continue
            }
        }
        return c
    }
}
