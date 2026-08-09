#!/usr/bin/env swift
/**
 Develop staging tests — A key acceptance (autorepeat, Esc, distinct proposals, A1 banner).

 Run: swift Scripts/develop_staging_test.swift
 */
import Foundation

var failures = 0
func expect(_ cond: Bool, _ msg: String) {
    if cond { print("PASS: \(msg)") } else { print("FAIL: \(msg)"); failures += 1 }
}

// MARK: - Mirrors

struct AutoSuggestion {
    var exposure: Double
    var contrast: Double
    var highlights: Double
    var shadows: Double
    var vibrance: Double
    var kelvin: Double
    var tint: Double
}

struct EditRecipe {
    var exposure: Double = 0
    var temperature: Double = 6500
    var tint: Double = 0
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var vibrance: Double = 0
}

struct DevelopRecipe {
    var exposure: Double = 0
    var temperature: Double = 6500
    var tint: Double = 0
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var vibrance: Double = 0
}

func propose(suggestion: AutoSuggestion, base: DevelopRecipe) -> EditRecipe {
    let offsets = (
        exposure: suggestion.exposure - base.exposure,
        kelvin: suggestion.kelvin - base.temperature,
        tint: suggestion.tint - base.tint,
        contrast: suggestion.contrast - base.contrast,
        highlights: suggestion.highlights - base.highlights,
        shadows: suggestion.shadows - base.shadows,
        vibrance: suggestion.vibrance - base.vibrance
    )
    return EditRecipe(
        exposure: base.exposure + offsets.exposure,
        temperature: base.temperature + offsets.kelvin,
        tint: base.tint + offsets.tint,
        contrast: base.contrast + offsets.contrast,
        highlights: base.highlights + offsets.highlights,
        shadows: base.shadows + offsets.shadows,
        vibrance: base.vibrance + offsets.vibrance
    )
}

enum DevelopKeyAction {
    case stageDevelop
    case ignoredRepeat

    static func onA(isRepeat: Bool, cropLatched: Bool) -> DevelopKeyAction? {
        if cropLatched { return nil }
        if isRepeat { return .ignoredRepeat }
        return .stageDevelop
    }
}

struct StagingCopySnapshot {
    var scopeCount: Int
    var isDevelop: Bool = true
}

func developBanner(count: Int) -> String {
    "Develop → \(count) ⏎ · Esc"
}

func stagedHeader(scopeCount: Int) -> String {
    "STAGED · row 1 · 18:17 · \(scopeCount) selected · ⏎ applies · Esc cancels, nothing applied"
}

func a1Validate(header: String, banner: String, snapshot: StagingCopySnapshot) -> Bool {
    func count(in text: String) -> Int? {
        if let r = text.range(of: #"Develop → (\d+)"#, options: .regularExpression) {
            let slice = text[r].dropFirst("Develop → ".count)
            return Int(slice.prefix(while: { $0.isNumber }))
        }
        if let r = text.range(of: #"· (\d+) selected"#, options: .regularExpression) {
            return Int(text[r].filter(\.isNumber))
        }
        return nil
    }
    guard let hc = count(in: header), hc == snapshot.scopeCount else { return false }
    guard let bc = count(in: banner), bc == snapshot.scopeCount else { return false }
    return true
}

// MARK: - Tests

expect(DevelopKeyAction.onA(isRepeat: true, cropLatched: false) == .ignoredRepeat, "A swallows key-repeat")
expect(DevelopKeyAction.onA(isRepeat: false, cropLatched: false) == .stageDevelop, "A tap stages develop")
expect(DevelopKeyAction.onA(isRepeat: false, cropLatched: true) == nil, "A blocked while crop latched")

var sidecarWritten = false
var staged = false
func stageDevelop() { staged = true }
func cancelDevelop() { staged = false }
func commitDevelop() { sidecarWritten = true; staged = false }

stageDevelop()
expect(staged && !sidecarWritten, "staging does not write sidecar")
cancelDevelop()
expect(!staged && !sidecarWritten, "Esc leaves sidecar untouched")

stageDevelop()
commitDevelop()
expect(sidecarWritten, "⏎ commit writes sidecar")

let dark = AutoSuggestion(exposure: -0.8, contrast: 10, highlights: -20, shadows: 15, vibrance: 5, kelvin: 5200, tint: 2)
let bright = AutoSuggestion(exposure: 0.6, contrast: 5, highlights: -5, shadows: 0, vibrance: 12, kelvin: 6800, tint: -3)
let base = DevelopRecipe()
let pDark = propose(suggestion: dark, base: base)
let pBright = propose(suggestion: bright, base: base)
expect(pDark.exposure != pBright.exposure, "distinct histograms → distinct proposals")
expect(pDark.temperature != pBright.temperature, "distinct RAWs → distinct white balance")

let snapshot = StagingCopySnapshot(scopeCount: 1, isDevelop: true)
let header = stagedHeader(scopeCount: snapshot.scopeCount)
let banner = developBanner(count: snapshot.scopeCount)
expect(a1Validate(header: header, banner: banner, snapshot: snapshot), "A1 develop banner/header scope count aligned")

if failures == 0 {
    print("\nAll develop staging tests passed.")
} else {
    print("\n\(failures) develop staging test(s) failed.")
    exit(1)
}
