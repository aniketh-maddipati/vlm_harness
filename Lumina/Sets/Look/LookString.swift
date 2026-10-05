import Foundation

/// The look string: the only state of the Edit step (roadmap "Rendering contract"). Every preview
/// is `lumina://render/<rel>?look=<string>&px=<n>`; every export carries the same string; the
/// session keeps it per photo (`look`) and per row (`rowLook`). It is never written to XMP.
///
///     ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 shp:30 vig:0 crop:x,y,w,h/r rot:90
///
/// Keys may come in any order; a missing key means its reset value (`wb` missing = as shot,
/// `crop` missing = whole frame, `rot` missing = no turn). Unknown keys are an error, so a typo can't silently render a
/// different look. `format` writes the canonical form (fixed key order, fixed precision, zeros
/// unsigned), so two equal looks are equal strings and cache keys.
nonisolated struct Look: Equatable, Sendable {
    /// Exposure in stops, −5 … +5, step 0.05.
    var ev: Double = 0
    /// White balance: Kelvin 2000 … 50000 (log scale in the UI) and tint −150 … +150. Nil = as shot.
    var wb: WhiteBalance?
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var whites: Double = 0
    var blacks: Double = 0
    var vibrance: Double = 0
    var saturation: Double = 0
    var clarity: Double = 0
    /// Sharpening amount 0 … 150.
    var sharpen: Double = 0
    /// Post-crop vignette −100 … +100 (negative darkens the corners, as in Lightroom).
    var vignette: Double = 0
    /// The vignette's shape, `vigs:midpoint,roundness,feather,highlights` (Lightroom's four
    /// sliders and its ranges). Written only when one of them is off its reset; it draws nothing
    /// while `vig` is 0.
    var vignetteShape = VignetteShape()
    /// The tone curve: `tc:dark,mid,light` (the three region sliders) and the point curves
    /// `crv:` (all channels), `crvr:`, `crvg:`, `crvb:` as `x,y/x,y/…`. Each written only when set.
    var curve = ToneCurve()
    /// The colour mixer: hue, saturation and luminance per colour, `mixh:`, `mixs:`, `mixl:`,
    /// each eight values in `Mixer.colours`' order. Each written only when one of its eight is set.
    var mixer = Mixer()
    /// Black and white: chroma to zero in the colour stage. Optional key `bw:1`.
    var bw: Bool = false
    var crop: Crop?
    /// A quarter turn of the picture, clockwise: 0, 90, 180 or 270 (`rot:90`). Geometry like the
    /// crop, and applied after it: the crop box and its straighten angle stay in the frame as
    /// shot (the page's crop tool works there), then the cropped picture is turned.
    var rot: Int = 0
    /// Detail ▸ luminance noise reduction, 0 … 100, the RAW stage's
    /// `luminanceNoiseReductionAmount` (RAW 9 §6). Nil = the decoder's default. A develop
    /// parameter, not a look stage: it changes the `base`, not the graph on top of it.
    var nr: Double?

    struct WhiteBalance: Equatable, Sendable {
        var kelvin: Double
        var tint: Double
    }

    /// Fractions of the developed frame (0 … 1) plus a straighten angle in degrees.
    struct Crop: Equatable, Sendable {
        var x: Double, y: Double, w: Double, h: Double
        var rotate: Double = 0
    }

    /// Midpoint 0 … 100 (50): how far from the centre the vignette starts. Roundness −100 … +100
    /// (0): 0 is the frame's own ellipse, above it a circle, below it the frame's rectangle.
    /// Feather 0 … 100 (50): the width of the falloff. Highlights 0 … 100 (0): how much of a
    /// darkening vignette bright pixels are spared. The page's and Lightroom's scales, 1:1
    /// (`LookMath.VignetteForm`).
    struct VignetteShape: Equatable, Sendable {
        var midpoint: Double = 50, roundness: Double = 0, feather: Double = 50, highlights: Double = 0
        var isDefault: Bool { self == VignetteShape() }
    }
    static let vignetteShapeRanges = [Range(min: 0, max: 100, step: 1), Range(min: -100, max: 100, step: 1), Range(min: 0, max: 100, step: 1), Range(min: 0, max: 100, step: 1)]

    /// The tone curve as the page keeps it. `dark`, `mid`, `light` (−50 … +50) are the region
    /// sliders: each moves the curve at a quarter, a half and three quarters of the way from
    /// black to white. `rgb`, `red`, `green`, `blue` are point curves: 2 to `maxPoints` points,
    /// x and y in 0 … 1 (0 black, 1 white, display-referred), x strictly increasing, four
    /// decimals. A curve that is the straight line from 0,0 to 1,1 is no curve (nil).
    ///
    /// As on the page, the all-channels curve is `rgb` when it is set and the three region
    /// sliders otherwise: once the user has edited points, the page keeps the sliders only as a
    /// read-out of the same curve (its value at 0.25 / 0.5 / 0.75), so with `rgb` set the stage
    /// does not read them. The string carries both; neither is derived here.
    ///
    /// y is not required to rise: the string is the page's state, points and all. The stage
    /// repairs a falling curve when it renders (`LookMath.curveSpline`), so the transfer never falls.
    struct ToneCurve: Equatable, Sendable {
        struct Point: Equatable, Sendable {
            var x: Double, y: Double
            init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
        }
        var dark = 0.0, mid = 0.0, light = 0.0
        var rgb: [Point]?, red: [Point]?, green: [Point]?, blue: [Point]?

        /// Whether the stage has anything to do. (Points that happen to lie on the diagonal still
        /// count: `parse` never produces them.)
        var isNeutral: Bool { rgb == nil && red == nil && green == nil && blue == nil && dark == 0 && mid == 0 && light == 0 }

        /// The page keeps points at least 0.02 apart in x: at most 51. Room to spare.
        static let maxPoints = 64
        static let regionRange = Range(min: -50, max: 50, step: 1)
        /// The point-curve keys, in the order `format` writes them.
        static let pointKeys: [(key: String, field: WritableKeyPath<ToneCurve, [Point]?>)] = [("crv", \.rgb), ("crvr", \.red), ("crvg", \.green), ("crvb", \.blue)]

        static func isIdentity(_ p: [Point]) -> Bool {
            p.count >= 2 && p.first!.x == 0 && p.last!.x == 1 && p.allSatisfy { $0.x == $0.y }
        }
    }

    /// The colour mixer's 24 values, −100 … +100: per colour a hue shift, a saturation change and
    /// a luminance change. The colours and their order are the page's (`hue_red` … `lum_magenta`)
    /// and Lightroom's.
    struct Mixer: Equatable, Sendable {
        static let colours = ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"]
        static let range = Range(min: -100, max: 100, step: 1)
        var hue = [Double](repeating: 0, count: 8)
        var saturation = [Double](repeating: 0, count: 8)
        var luminance = [Double](repeating: 0, count: 8)
        var isNeutral: Bool { !(hue + saturation + luminance).contains { $0 != 0 } }

        /// The three keys, in the order `format` writes them.
        static let keys: [(key: String, field: WritableKeyPath<Mixer, [Double]>)] = [("mixh", \.hue), ("mixs", \.saturation), ("mixl", \.luminance)]
    }

    struct ParseError: Error, CustomStringConvertible, Equatable {
        let description: String
    }

    /// Slider ranges (roadmap): the parser clamps into them, so a look from an older session or a
    /// hand-typed one can't ask a stage for a value its fit never saw.
    struct Range: Sendable { let min: Double, max: Double, step: Double }
    static let ranges: [String: Range] = [
        "ev": Range(min: -5, max: 5, step: 0.05),
        "con": Range(min: -100, max: 100, step: 1), "hl": Range(min: -100, max: 100, step: 1),
        "sh": Range(min: -100, max: 100, step: 1), "wh": Range(min: -100, max: 100, step: 1),
        "bl": Range(min: -100, max: 100, step: 1), "vib": Range(min: -100, max: 100, step: 1),
        "sat": Range(min: -100, max: 100, step: 1), "clr": Range(min: -100, max: 100, step: 1),
        "shp": Range(min: 0, max: 150, step: 1), "vig": Range(min: -100, max: 100, step: 1),
    ]
    static let kelvinRange = Range(min: 2000, max: 50000, step: 1)
    static let tintRange = Range(min: -150, max: 150, step: 1)
    static let nrRange = Range(min: 0, max: 100, step: 1)
    /// Canonical key order; also the order `format` writes.
    static let keys = ["ev", "wb", "con", "hl", "sh", "wh", "bl", "vib", "sat", "clr", "shp", "vig", "vigs", "tc", "crv", "crvr", "crvg", "crvb", "mixh", "mixs", "mixl", "nr", "bw", "crop", "rot"]
    /// The plain numeric sliders, key → field.
    static let sliders: [String: WritableKeyPath<Look, Double>] = [
        "ev": \.ev, "con": \.contrast, "hl": \.highlights, "sh": \.shadows, "wh": \.whites, "bl": \.blacks,
        "vib": \.vibrance, "sat": \.saturation, "clr": \.clarity, "shp": \.sharpen, "vig": \.vignette,
    ]

    /// True when every slider is at reset: the render is the RAW stage alone (plus crop and the
    /// develop's own noise reduction, `nr`, which lives in the RAW stage).
    var isNeutral: Bool {
        ev == 0 && wb == nil && contrast == 0 && highlights == 0 && shadows == 0 && whites == 0 && blacks == 0
            && vibrance == 0 && saturation == 0 && clarity == 0 && sharpen == 0 && vignette == 0 && !bw
            && curve.isNeutral && mixer.isNeutral
    }

    static func clamp(_ v: Double, _ r: Range) -> Double {
        let c = min(r.max, max(r.min, v))
        return c.isFinite ? c : 0
    }

    // MARK: Parse

    /// `parse("")` and `parse("none")` are the neutral look.
    static func parse(_ s: String) throws -> Look {
        var look = Look()
        let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "none" { return look }
        var seen: Set<String> = []
        for token in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            guard let colon = token.firstIndex(of: ":") else { throw ParseError(description: "'\(token)' has no ':'") }
            let key = String(token[..<colon]), raw = String(token[token.index(after: colon)...])
            guard !seen.contains(key) else { throw ParseError(description: "'\(key)' given twice") }
            seen.insert(key)
            func number(_ t: String, _ what: String) throws -> Double {
                guard let v = Double(t), v.isFinite else { throw ParseError(description: "\(what): '\(t)' is not a number") }
                return v
            }
            if let field = Self.sliders[key] {
                let v = try number(raw, key)
                look[keyPath: field] = clamp(v, ranges[key]!)
                continue
            }
            /// `a,b,c`: exactly `count` numbers, each clamped into its range.
            func list(_ what: String, _ ranges: [Range]) throws -> [Double] {
                let parts = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                guard parts.count == ranges.count else { throw ParseError(description: "\(key) wants \(what), got '\(raw)'") }
                return try zip(parts, ranges).map { clamp(try number($0, key), $1) }
            }
            if let curveKey = ToneCurve.pointKeys.first(where: { $0.key == key }) {
                // `x,y/x,y/…`: numbers clamp into 0 … 1 (four decimals); the shape of the list is checked.
                let pts = try raw.split(separator: "/", omittingEmptySubsequences: false).map { part -> ToneCurve.Point in
                    let xy = part.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                    guard xy.count == 2 else { throw ParseError(description: "\(key) wants x,y/x,y/…, got '\(raw)'") }
                    let unit = { (t: String) in (min(1, max(0, try number(t, key))) * 10000).rounded() / 10000 }
                    return ToneCurve.Point(try unit(xy[0]), try unit(xy[1]))
                }
                guard pts.count >= 2, pts.count <= ToneCurve.maxPoints else { throw ParseError(description: "\(key) wants 2 to \(ToneCurve.maxPoints) points, got \(pts.count)") }
                guard zip(pts, pts.dropFirst()).allSatisfy({ $0.x < $1.x }) else { throw ParseError(description: "\(key): x must increase from point to point, got '\(raw)'") }
                look.curve[keyPath: curveKey.field] = ToneCurve.isIdentity(pts) ? nil : pts
                continue
            }
            if let mixKey = Mixer.keys.first(where: { $0.key == key }) {
                look.mixer[keyPath: mixKey.field] = try list("eight values (\(Mixer.colours.joined(separator: ",")))", Array(repeating: Mixer.range, count: Mixer.colours.count))
                continue
            }
            switch key {
            case "tc":
                let v = try list("dark,mid,light", [ToneCurve.regionRange, ToneCurve.regionRange, ToneCurve.regionRange])
                look.curve.dark = v[0]; look.curve.mid = v[1]; look.curve.light = v[2]
            case "vigs":
                let v = try list("midpoint,roundness,feather,highlights", vignetteShapeRanges)
                look.vignetteShape = VignetteShape(midpoint: v[0], roundness: v[1], feather: v[2], highlights: v[3])
            case "bw":
                look.bw = raw == "1" || raw == "true"
            case "nr":
                look.nr = clamp(try number(raw, "nr"), nrRange)
            case "wb":
                let parts = raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 2 else { throw ParseError(description: "wb wants kelvin/tint, got '\(raw)'") }
                let kelvin = try number(parts[0], "wb kelvin"), tint = try number(parts[1], "wb tint")
                look.wb = WhiteBalance(kelvin: clamp(kelvin, kelvinRange), tint: clamp(tint, tintRange))
            case "crop":
                let halves = raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                let box = halves[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                guard halves.count <= 2, box.count == 4 else { throw ParseError(description: "crop wants x,y,w,h[/r], got '\(raw)'") }
                let v = try box.map { try number($0, "crop") }
                var c = Crop(x: min(1, max(0, v[0])), y: min(1, max(0, v[1])), w: min(1, max(0, v[2])), h: min(1, max(0, v[3])))
                if halves.count == 2 {
                    let r = try number(halves[1], "crop rotate")
                    c.rotate = min(45, max(-45, r))
                }
                guard c.w > 0, c.h > 0, c.x + c.w <= 1.0001, c.y + c.h <= 1.0001 else { throw ParseError(description: "crop '\(raw)' leaves the frame") }
                look.crop = c
            case "rot":
                // Any whole number of quarter turns (-90 is 270, 360 is 0); anything else is a typo.
                let v = try number(raw, "rot")
                guard v == v.rounded(), abs(v) <= 3600, Int(v) % 90 == 0 else { throw ParseError(description: "rot wants 0, 90, 180 or 270, got '\(raw)'") }
                look.rot = ((Int(v) % 360) + 360) % 360
            default:
                throw ParseError(description: "unknown key '\(key)'")
            }
        }
        return look
    }

    // MARK: Format

    /// Canonical text. Reset values are written too (the page can diff two looks by eye); `wb`,
    /// `vigs`, the curve keys, the mixer keys, `nr`, `bw`, `crop` and `rot` only when set.
    func format() -> String {
        func signed(_ v: Double, _ decimals: Int) -> String {
            let r = (v * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
            if r == 0 { return decimals == 0 ? "0" : String(format: "%.\(decimals)f", 0.0) }
            return (r > 0 ? "+" : "") + String(format: "%.\(decimals)f", r)
        }
        var out = ["ev:\(signed(ev, 2))"]
        if let wb { out.append("wb:\(Int(wb.kelvin.rounded()))/\(signed(wb.tint, 0))") }
        out += ["con:\(signed(contrast, 0))", "hl:\(signed(highlights, 0))", "sh:\(signed(shadows, 0))",
                "wh:\(signed(whites, 0))", "bl:\(signed(blacks, 0))", "vib:\(signed(vibrance, 0))",
                "sat:\(signed(saturation, 0))", "clr:\(signed(clarity, 0))", "shp:\(Int(sharpen.rounded()))",
                "vig:\(signed(vignette, 0))"]
        if !vignetteShape.isDefault {
            let s = vignetteShape
            out.append("vigs:\(Int(s.midpoint.rounded())),\(signed(s.roundness, 0)),\(Int(s.feather.rounded())),\(Int(s.highlights.rounded()))")
        }
        if curve.dark != 0 || curve.mid != 0 || curve.light != 0 { out.append("tc:\(signed(curve.dark, 0)),\(signed(curve.mid, 0)),\(signed(curve.light, 0))") }
        for (key, field) in ToneCurve.pointKeys {
            guard let pts = curve[keyPath: field] else { continue }
            // Four decimals, trailing zeros dropped: 0.25, 1, 0.
            func unit(_ v: Double) -> String {
                var t = String(format: "%.4f", v)
                while t.hasSuffix("0") { t.removeLast() }
                if t.hasSuffix(".") { t.removeLast() }
                return t
            }
            out.append("\(key):" + pts.map { "\(unit($0.x)),\(unit($0.y))" }.joined(separator: "/"))
        }
        for (key, field) in Mixer.keys {
            let v = mixer[keyPath: field]
            if v.contains(where: { $0 != 0 }) { out.append("\(key):" + v.map { signed($0, 0) }.joined(separator: ",")) }
        }
        if let nr { out.append("nr:\(Int(nr.rounded()))") }
        if bw { out.append("bw:1") }
        if let c = crop {
            let f = { (v: Double) in String(format: "%.4f", v) }
            out.append("crop:\(f(c.x)),\(f(c.y)),\(f(c.w)),\(f(c.h))" + (c.rotate == 0 ? "" : "/\(String(format: "%.2f", c.rotate))"))
        }
        if rot != 0 { out.append("rot:\(rot)") }
        return out.joined(separator: " ")
    }

    /// The slider a sweep names (Lightroom's develop-setting names, as `lr_sweep.lua` and
    /// `import_refs.py` write them) → the look with only that slider set. Nil for a name that is
    /// not one of the twelve.
    static func single(_ slider: String, _ value: Double, asShot: WhiteBalance?) -> Look? {
        var l = Look()
        switch slider {
        case "Exposure": l.ev = value
        case "Temperature": l.wb = WhiteBalance(kelvin: value, tint: asShot?.tint ?? 0)
        case "Tint": l.wb = WhiteBalance(kelvin: asShot?.kelvin ?? 5500, tint: value)
        case "Contrast": l.contrast = value
        case "Highlights": l.highlights = value
        case "Shadows": l.shadows = value
        case "Whites": l.whites = value
        case "Blacks": l.blacks = value
        case "Vibrance": l.vibrance = value
        case "Saturation": l.saturation = value
        case "Clarity": l.clarity = value
        case "Sharpness", "Sharpening": l.sharpen = value
        default: return nil
        }
        return l
    }
}
