import Foundation

/// JavaScript number semantics the cull core relies on. The port of `lumina-core.js`
/// must print numbers exactly as the prototype does (XMP sidecars are diffed byte-for-byte),
/// so these follow ECMA-262 rather than `String(format:)` rounding.
nonisolated enum CullCoreJSNumber {
    /// `Number.prototype.toFixed(digits)` — ties round away from zero on the exact binary value.
    static func toFixed(_ value: Double, _ digits: Int) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
        if abs(value) >= 1e21 { return numberString(value) }
        let negative = value < 0
        // %.1100f prints the exact binary expansion (a double's fraction never needs more than 1074 digits).
        let exact = String(format: "%.1100f", abs(value))
        let parts = exact.split(separator: ".", maxSplits: 1)
        var intDigits = Array(parts[0]).map { Int(String($0))! }
        let fracDigits = Array(parts.count > 1 ? parts[1] : "").map { Int(String($0))! }
        var kept = Array(fracDigits.prefix(digits))
        while kept.count < digits { kept.append(0) }
        let rest = fracDigits.dropFirst(digits)
        if let first = rest.first, first >= 5 {
            // n/10^f closest to x; on an exact tie pick the larger n.
            var carry = 1
            for i in stride(from: kept.count - 1, through: 0, by: -1) where carry == 1 {
                kept[i] += 1
                if kept[i] == 10 { kept[i] = 0 } else { carry = 0 }
            }
            for i in stride(from: intDigits.count - 1, through: 0, by: -1) where carry == 1 {
                intDigits[i] += 1
                if intDigits[i] == 10 { intDigits[i] = 0 } else { carry = 0 }
            }
            if carry == 1 { intDigits.insert(1, at: 0) }
        }
        var out = intDigits.map(String.init).joined()
        if digits > 0 { out += "." + kept.map(String.init).joined() }
        // ECMA-262: a negative input keeps its sign even when it rounds to zero; -0 does not.
        return negative ? "-" + out : out
    }

    /// `Math.round` — rounds half toward +∞.
    static func round(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        let floor = value.rounded(.down)
        return value - floor >= 0.5 ? floor + 1 : floor
    }

    /// `String(n)` for the integral values the core prints (Math.round results).
    static func numberString(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
        if value == value.rounded(), abs(value) < 1e21 {
            if value == 0 { return "0" }
            return String(format: "%.0f", value)
        }
        // Non-integral or huge: JS shortest round-trip form; Swift's description matches for these ranges
        // except exponent spelling, which the core never hits.
        return "\(value)"
    }

    /// JavaScript truthiness for an optional number.
    static func truthy(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value != 0 && !value.isNaN
    }
}
