import Foundation

// WP-6. What the Variations grid offers for a setting (README §3 "Overlays"; the prototype's
// `varDown`, and its white-balance and vignette grids). Pure: a key and the photo's look in,
// the cells out. The model (`AppModel+Overlays`) decides when the grid opens and what applies.

public struct VariationCell: Equatable, Sendable {
    /// "−¼ EV", "now", "warmer", "5820K +20", "none".
    public var label: String
    /// The settings this cell sets on top of the photo's look.
    public var values: [String: Double]
    /// The cell that changes nothing.
    public var isNow: Bool
    public init(label: String, values: [String: Double], isNow: Bool) { self.label = label; self.values = values; self.isNow = isNow }
}

public struct VariationSpec: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// below / now / above.
        case three
        /// Temperature (columns) × tint (rows), 3 × 3.
        case grid
        /// Vignette: as it is / the other one.
        case two
    }
    /// The setting the grid is about (`debug.state.spec`).
    public var key: String
    public var kind: Kind
    public var cells: [VariationCell]
    public var columns: Int
    /// The cell highlighted when the grid opens: always the one that changes nothing, so a
    /// hold and release without choosing never edits the photo.
    public var initial: Int
    public var title: String
    /// Right of the title: the step sizes ("±12% · ±20"), empty when the labels say it.
    public var step: String

    public var rows: Int { (cells.count + columns - 1) / max(1, columns) }

    /// The highlighted cell after an arrow key. Rows only exist in the 3 × 3 grid; two or three
    /// cells are one line (drawn stacked in a tall canvas), so ↑ ↓ walk it like ← →.
    public func moved(from index: Int, dx: Int, dy: Int) -> Int {
        guard !cells.isEmpty else { return 0 }
        let i = clamp(0, index, cells.count - 1)
        guard kind == .grid else { return clamp(0, i + dx + dy, cells.count - 1) }
        let r = clamp(0, i / columns + dy, rows - 1), c = clamp(0, i % columns + dx, columns - 1)
        return min(cells.count - 1, r * columns + c)
    }
}

public enum Variations {
    /// V released sooner than this was a tap: the grid stays open and nothing applies (prototype: 280 ms).
    public static let tapThreshold: TimeInterval = 0.28
    /// Applying waits this long and is dropped if the photo changed meanwhile (R-06).
    public static let applyWindow: TimeInterval = 0.12

    /// The prototype's comparison step per setting; a variation is half of it either way
    /// (Exposure ±¼ EV, Temperature ±6 %, Contrast ±10 …).
    public static func comparisonStep(_ key: String) -> Double {
        switch key {
        case "ev": 0.5
        case "wb": 0.12
        case "tint", "con", "sat", "nr": 20
        case "hl", "sh", "vRound", "vHl": 25
        case "cDark", "cMid", "cLight", "vMid", "vFeather": 15
        case "vig", "shp": 30
        default: EditSetting.byKey[key]?.section == .colour ? 20 : (EditSetting.byKey[key]?.step ?? 1)
        }
    }
    /// Tint step of the white-balance grid.
    public static let gridTintStep = 20.0
    /// The vignette the two-cell grid offers when the photo has none.
    public static let vignetteOffer = -30.0

    /// "+12", "−30", "0": a typographic minus, as the prototype writes numbers.
    public static func signed(_ v: Double, decimals: Int = 0) -> String {
        let r = abs(v) < 0.5 * pow(10, -Double(decimals)) ? 0 : v
        return (r > 0 ? "+" : r < 0 ? "−" : "") + String(format: "%.\(decimals)f", abs(r))
    }

    /// "Exposure", "Red saturation".
    public static func name(_ key: String) -> String {
        guard let s = EditSetting.byKey[key] else { return key }
        guard s.section == .colour, let axis = key.split(separator: "_").first else { return s.label }
        return s.label + " " + (["hue": "hue", "sat": "saturation", "lum": "luminance"][String(axis)] ?? String(axis))
    }

    /// The value as the sliders write it: "+0.25 EV", "5510 K", "−30", "40".
    public static func format(_ key: String, _ v: Double) -> String {
        guard let s = EditSetting.byKey[key] else { return signed(v) }
        if key == "ev" { return signed(v, decimals: 2) + " EV" }
        if key == "wb" { return "\(Int(v.rounded())) K" }
        return s.min >= 0 ? "\(Int(v.rounded()))" : signed(v.rounded())
    }

    /// The grid for `key` on a photo whose look is `look`. `whiteBalance` asks for the
    /// temperature × tint grid (the pointer is on Tint, or the white picker is on).
    public static func spec(key: String, whiteBalance: Bool = false, look: Look) -> VariationSpec? {
        func value(_ k: String) -> Double { look[k] ?? EditSetting.byKey[k]?.def ?? 0 }
        if whiteBalance, let wb = EditSetting.byKey["wb"], let tint = EditSetting.byKey["tint"] {
            let f = comparisonStep("wb"), t0 = value("tint"), k0 = value("wb")
            var cells: [VariationCell] = []
            for r in [1.0, 0, -1] { for c in [-1.0, 0, 1] {
                let k = wb.clamp(k0 * pow(1 + f, c)), t = tint.clamp(t0 + r * gridTintStep)
                cells.append(VariationCell(label: "\(Int(k))K \(signed(t))", values: ["wb": k, "tint": t], isNow: r == 0 && c == 0))
            } }
            return VariationSpec(key: "wb", kind: .grid, cells: cells, columns: 3, initial: 4, title: "White balance",
                                 step: "±\(Int((f * 100).rounded()))% · ±\(Int(gridTintStep))")
        }
        guard let s = EditSetting.byKey[key] else { return nil }
        let v = value(key)
        if key == "vig" {
            let other = v == 0 ? vignetteOffer : 0
            let cells = [v, other].enumerated().map { i, x in VariationCell(label: x == 0 ? "none" : signed(x), values: [key: x], isNow: i == 0) }
            return VariationSpec(key: key, kind: .two, cells: cells, columns: 2, initial: 0, title: "Variations · " + name(key), step: "")
        }
        let st = comparisonStep(key) / 2
        let cells = [-1.0, 0, 1].map { d -> VariationCell in
            // The prototype rounds before clamping: whole kelvin for temperature, two decimals for exposure, whole numbers for the rest.
            let raw = key == "wb" ? (v * (1 + d * st)).rounded() : key == "ev" ? ((v + d * st) * 100).rounded() / 100 : (v + d * st).rounded()
            let label: String = d == 0 ? "now" : key == "wb" ? (d < 0 ? "cooler" : "warmer")
                : (d < 0 ? "−" : "+") + (key == "ev" ? (st == 0.25 ? "¼" : String(format: "%.2f", st)) + " EV" : "\(Int(st.rounded()))")
            return VariationCell(label: label, values: [key: d == 0 ? v : s.clamp(raw)], isNow: d == 0)
        }
        return VariationSpec(key: key, kind: .three, cells: cells, columns: 3, initial: 1, title: "Variations · " + name(key), step: "")
    }
}
