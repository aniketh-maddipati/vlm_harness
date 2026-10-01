import Foundation

// WP-5. How a setting's value reads, where it sits on its track, and the stand-in for Auto.
// No state: the controls column, the toasts and the tests all go through here.

public enum EditFormat {
    /// "+0.15 EV", "5300 K", "+12", "−8", "0"; settings that can't go below zero show no sign.
    public static func value(_ key: String, _ v: Double) -> String {
        let v = v.isFinite ? v : (EditSetting.byKey[key]?.def ?? 0)
        switch key {
        case "ev": return signed(v, decimals: 2) + " EV"
        case "wb": return "\(Int(v.rounded())) K"
        default:
            if let s = EditSetting.byKey[key], s.min >= 0 { return String(Int(v.rounded())) }
            return signed(v.rounded(), decimals: 0)
        }
    }

    /// "+0.25", "−3", "0" (a real minus sign, as in the design).
    public static func signed(_ v: Double, decimals: Int) -> String {
        let p = pow(10, Double(decimals)), r = (v * p).rounded() / p
        let body = String(format: "%.\(decimals)f", abs(r))
        return (r > 0 ? "+" : r < 0 ? "−" : "") + body
    }

    /// What the value field starts with when a number is clicked: the bare number.
    public static func editable(_ key: String, _ v: Double) -> String {
        if key == "wb" { return String(Int(v.rounded())) }
        let step = EditSetting.byKey[key]?.step ?? 1
        if step >= 1 { return String(Int(v.rounded())) }
        var t = String(format: "%.2f", v)
        while t.contains("."), t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t == "-0" ? "0" : t
    }

    /// A typed value: "−" counts as minus, units and spaces are dropped, junk gives nil.
    public static func parse(_ text: String) -> Double? {
        let t = text.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: ",", with: ".")
            .filter { "0123456789.+-".contains($0) }
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return v
    }

    /// "Exposure", "Red saturation": the name a toast, the hint line and VoiceOver use.
    public static func label(_ key: String) -> String {
        guard let s = EditSetting.byKey[key] else { return key }
        guard s.section == .colour, let axis = key.split(separator: "_").first.map(String.init) else { return s.label }
        return s.label + " " + axisName(axis).lowercased()
    }
    public static func axisName(_ axis: String) -> String {
        switch axis { case "hue": "Hue"; case "lum": "Luminance"; default: "Saturation" }
    }
    /// The colour of a colour setting ("sat_red" → "red"), nil for the others.
    public static func colour(of key: String) -> String? {
        guard EditSetting.byKey[key]?.section == .colour else { return nil }
        return key.split(separator: "_").last.map(String.init)
    }

    /// The hint line while the pointer is over a slider (README, "Slider row").
    public static func hint(_ key: String) -> String {
        "\(label(key)) — drag · ⇧ fine · double-click resets · click the number to type · hold V for variations"
    }
}

/// Where a value sits on its track (0…1), and back. Temperature is on a log scale.
public enum SliderScale {
    public static func position(_ s: EditSetting, _ v: Double) -> Double {
        let q = s.log ? log(max(v, 1) / s.min) / log(s.max / s.min) : (v - s.min) / (s.max - s.min)
        return q.isFinite ? min(1, max(0, q)) : 0
    }
    public static func value(_ s: EditSetting, at q: Double) -> Double {
        let q = min(1, max(0, q))
        return round(s, s.log ? s.min * pow(s.max / s.min, q) : s.min + q * (s.max - s.min))
    }
    /// Onto the setting's step and range, without the float dust (0.15, not 0.15000000000000002).
    public static func round(_ s: EditSetting, _ v: Double) -> Double {
        guard v.isFinite else { return s.def }
        let c = s.clamp(v)
        return (c * 100).rounded() / 100
    }
    /// Within 1.2 % of the default's place on the track: the drag snaps to it.
    public static let snapWithin = 0.012
}

/// The stand-in for Auto until the backend measures the picture: exposure from a brightness
/// figure derived from the photo's name (the design prototype's formula, so the demo card gives
/// the same numbers), a slightly warmer white balance, highlights down, shadows up.
public enum AutoLook {
    /// Exposure, temperature, highlights and shadows, each with a value (a default included, so
    /// laying it over an edit replaces all four).
    public static func make(for photo: Photo) -> Look {
        let h = brightness(photo)
        let ev = ((0.5 - h) * 1.2 / 0.05).rounded() * 0.05
        return ["ev": EditSetting.byKey["ev"].map { SliderScale.round($0, ev) + 0 } ?? 0,
                "wb": ((EditSetting.asShotKelvin + 400) / 100).rounded() * 100, "hl": -22, "sh": 18]
    }
    /// 0…1, stable per photo.
    static func brightness(_ p: Photo) -> Double {
        let digits = p.id.filter(\.isNumber)
        let n = Int(digits.suffix(9)) ?? p.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 1_000_003 }
        return Double((n * 37 + p.scene * 11) % 97) / 97
    }
}
