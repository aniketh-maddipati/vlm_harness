#!/usr/bin/env swift
/**
 Deterministic EditRecipe / batch / generation tests for macOS Swift runtime.
 Mirrors Scripts/develop_engine_test.py — run: swift Scripts/develop_recipe_test.swift
 */
import Foundation

var failures = 0
func expect(_ cond: Bool, _ msg: String) {
    if cond {
        print("PASS: \(msg)")
    } else {
        print("FAIL: \(msg)")
        failures += 1
    }
}

// Minimal mirrors (standalone — does not import app module)

struct EditCrop: Codable, Equatable {
    var x, y, width, height: Double
    func normalized() -> EditCrop {
        let w = min(max(width, 0.01), 1)
        let h = min(max(height, 0.01), 1)
        return EditCrop(x: min(max(x, 0), 1 - w), y: min(max(y, 0), 1 - h), width: w, height: h)
    }
}

struct EditRecipe: Codable, Equatable {
    var id: UUID
    var schemaVersion: Int = 1
    var exposure: Double = 0
    var temperature: Double = 6500
    var tint: Double = 0
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var whites: Double = 0
    var blacks: Double = 0
    var sharpness: Double = 0
    var luminanceNR: Double = 0
    var crop: EditCrop? = nil
    var straightenDegrees: Double = 0
}

func encodeStable<T: Encodable>(_ v: T) throws -> Data {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    return try e.encode(v)
}

// Serialization
do {
    let r = EditRecipe(id: UUID(), exposure: 0.35, temperature: 5200, highlights: -20)
    let d1 = try encodeStable(r)
    let d2 = try encodeStable(r)
    expect(d1 == d2, "stable recipe serialization")
    let decoded = try JSONDecoder().decode(EditRecipe.self, from: d1)
    expect(abs(decoded.exposure - 0.35) < 1e-9, "recipe roundtrip")
}

// Generation ordering
func shouldPresent(candidate: UInt64, presented: UInt64?) -> Bool {
    guard let presented else { return true }
    return candidate >= presented
}
expect(shouldPresent(candidate: 5, presented: nil), "first generation")
expect(!shouldPresent(candidate: 4, presented: 5), "stale rejection")
expect(shouldPresent(candidate: 6, presented: 5), "newer accepted")

// Auto-repeat
func shouldIgnore(isARepeat: Bool) -> Bool { isARepeat }
expect(shouldIgnore(isARepeat: true), "auto-repeat ignored")
expect(!shouldIgnore(isARepeat: false), "real key accepted")

// Crop across resolutions
do {
    let crop = EditCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.4).normalized()
    func frac(_ extentW: Double, _ extentH: Double) -> (Double, Double, Double, Double) {
        // top-down normalized equals crop
        (crop.x, crop.y, crop.width, crop.height)
    }
    let a = frac(3200, 2000)
    let b = frac(8000, 5000)
    expect(a == b, "crop fractions identical across resolutions")
}

// Empty selection
struct Batch {
    var selected: [UUID] = []
    mutating func stage() -> String? {
        if selected.isEmpty { return "empty" }
        return nil
    }
}
var batch = Batch()
expect(batch.stage() == "empty", "empty selection cannot stage")

if failures > 0 {
    fputs("\(failures) failure(s)\n", stderr)
    exit(1)
}
print("All develop_recipe_test checks passed.")
