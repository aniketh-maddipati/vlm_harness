import Foundation

/// The look string: the only state of the Edit step (roadmap "Rendering contract"). Every preview
/// is `lumina://render/<rel>?look=<string>&px=<n>`; every export carries the same string; the
/// session keeps it per photo (`look`) and per row (`rowLook`). It is never written to XMP.
///
///     ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 shp:30 vig:0 crop:x,y,w,h/r
///
/// Keys may come in any order; a missing key means its reset value (`wb` missing = as shot,
/// `crop` missing = whole frame). Unknown keys are an error, so a typo can't silently render a
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
    /// Black and white: chroma to zero in the colour stage. Optional key `bw:1`.
    var bw: Bool = false
    var crop: Crop?

    struct WhiteBalance: Equatable, Sendable {
        var kelvin: Double
        var tint: Double
    }

    /// Fractions of the developed frame (0 … 1) plus a straighten angle in degrees.
    struct Crop: Equatable, Sendable {
        var x: Double, y: Double, w: Double, h: Double
        var rotate: Double = 0
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
    /// Canonical key order; also the order `format` writes.
    static let keys = ["ev", "wb", "con", "hl", "sh", "wh", "bl", "vib", "sat", "clr", "shp", "vig", "bw", "crop"]
    /// The plain numeric sliders, key → field.
    static let sliders: [String: WritableKeyPath<Look, Double>] = [
        "ev": \.ev, "con": \.contrast, "hl": \.highlights, "sh": \.shadows, "wh": \.whites, "bl": \.blacks,
        "vib": \.vibrance, "sat": \.saturation, "clr": \.clarity, "shp": \.sharpen, "vig": \.vignette,
    ]

    /// True when every slider is at reset: the render is the RAW stage alone (plus crop).
    var isNeutral: Bool {
        ev == 0 && wb == nil && contrast == 0 && highlights == 0 && shadows == 0 && whites == 0 && blacks == 0
            && vibrance == 0 && saturation == 0 && clarity == 0 && sharpen == 0 && vignette == 0 && !bw
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
            switch key {
            case "bw":
                look.bw = raw == "1" || raw == "true"
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
            default:
                throw ParseError(description: "unknown key '\(key)'")
            }
        }
        return look
    }

    // MARK: Format

    /// Canonical text. Reset values are written too (the page can diff two looks by eye); `wb`,
    /// `bw` and `crop` only when set.
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
        if bw { out.append("bw:1") }
        if let c = crop {
            let f = { (v: Double) in String(format: "%.4f", v) }
            out.append("crop:\(f(c.x)),\(f(c.y)),\(f(c.w)),\(f(c.h))" + (c.rotate == 0 ? "" : "/\(String(format: "%.2f", c.rotate))"))
        }
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
