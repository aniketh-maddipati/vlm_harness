#!/usr/bin/env swift
/**
 Lumina headless E2E audit — exercises extract / aspect / taste / timing / cluster-ish signals
 against a real shoot folder without launching the app UI.
 */
import Foundation
import ImageIO
import CoreGraphics

// MARK: - Config

let rawFolder = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/Users/aniketh/Pictures/jeevana_mehendi_2026_MATCHED_RAWS")
let jpgFolder = URL(fileURLWithPath: CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "/Users/aniketh/jeevana_mehendi_2026")
let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("lumina-e2e-\(UUID().uuidString)", isDirectory: true)
let sampleLimit = 24

struct Finding: Codable {
    var severity: String // bug | friction | frontier | pass
    var area: String
    var title: String
    var detail: String
}

struct Metrics: Codable {
    var rawCount: Int
    var jpgCount: Int
    var sampleSize: Int
    var extractOK: Int
    var extractFail: Int
    var aspectOutliers: Int
    var medianAspect: Double
    var extractP50ms: Double
    var extractP95ms: Double
    var tasteFilesWithCRS: Int
    var tasteKelvinMin: Double?
    var tasteKelvinMax: Double?
    var tasteKelvinMean: Double?
    var extremeKelvinCount: Int
    var portraitCount: Int
    var landscapeCount: Int
    var burstGuessCount: Int
    var exiftoolAvailable: Bool
}

var findings: [Finding] = []
func note(_ severity: String, _ area: String, _ title: String, _ detail: String) {
    findings.append(Finding(severity: severity, area: area, title: title, detail: detail))
    print("[\(severity.uppercased())] \(area): \(title) — \(detail)")
}

// MARK: - Helpers

func listPhotos(_ folder: URL, exts: Set<String>) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
        .filter { exts.contains($0.pathExtension.uppercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
}

func thumbnail(from url: URL, maxPixel: Int) -> (CGImage, Double)? {
    let t0 = CFAbsoluteTimeGetCurrent()
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    return (img, ms)
}

func percentile(_ values: [Double], p: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let s = values.sorted()
    let idx = min(Int(Double(s.count - 1) * p), s.count - 1)
    return s[idx]
}

func runExiftool(_ args: [String]) -> Data? {
    let path = "/usr/local/bin/exiftool"
    guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    try? p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    return out.fileHandleForReading.readDataToEndOfFile()
}

func parseDates(_ folder: URL) -> [String: Date] {
    guard let data = runExiftool(["-DateTimeOriginal", "-json", "-q", "-q", "-ext", "ARW", folder.path]),
          let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
    var map: [String: Date] = [:]
    for item in json {
        guard let src = item["SourceFile"] as? String,
              let raw = item["DateTimeOriginal"] as? String,
              let d = fmt.date(from: raw) else { continue }
        map[URL(fileURLWithPath: src).lastPathComponent] = d
    }
    return map
}

func tasteKelvins(_ folder: URL) -> [Double] {
    guard let data = runExiftool([
        "-json", "-q", "-q",
        "-XMP-crs:ColorTemperature", "-XMP-crs:Temperature", "-XMP-crs:Exposure2012",
        "-ext", "jpg", "-ext", "jpeg", folder.path
    ]),
    let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    var vals: [Double] = []
    for item in json {
        let k = (item["ColorTemperature"] as? NSNumber)?.doubleValue
            ?? (item["Temperature"] as? NSNumber)?.doubleValue
        if let k, k > 0 { vals.append(k) }
    }
    return vals
}

func laplacianVar(_ image: CGImage) -> Double {
    // Tiny grayscale variance proxy for blur
    guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return 0 }
    let w = image.width, h = image.height
    let bpp = max(image.bitsPerPixel / 8, 1)
    var gray = [Double](repeating: 0, count: w * h)
    for y in 0..<h {
        for x in 0..<w {
            let o = x * bpp + y * image.bytesPerRow
            if o + 2 >= CFDataGetLength(data) { continue }
            gray[y * w + x] = 0.299 * Double(ptr[o]) + 0.587 * Double(ptr[o + 1]) + 0.114 * Double(ptr[o + 2])
        }
    }
    var sum = 0.0, count = 0
    if w < 3 || h < 3 { return 0 }
    for y in 1..<(h - 1) {
        for x in 1..<(w - 1) {
            let c = gray[y * w + x]
            let lap = gray[(y - 1) * w + x] + gray[(y + 1) * w + x] + gray[y * w + x - 1] + gray[y * w + x + 1] - 4 * c
            sum += lap * lap
            count += 1
        }
    }
    return count > 0 ? sum / Double(count) : 0
}

// MARK: - Run

try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: workDir) }

let raws = listPhotos(rawFolder, exts: ["ARW", "CR2", "CR3", "NEF", "DNG", "JPG", "JPEG", "HEIC"])
let jpgs = listPhotos(jpgFolder, exts: ["JPG", "JPEG", "HEIC"])
print("RAW/media: \(raws.count) in \(rawFolder.path)")
print("JPG taste: \(jpgs.count) in \(jpgFolder.path)")

if raws.isEmpty {
    note("bug", "import", "No media found", "Folder empty or wrong path: \(rawFolder.path)")
}

let sample = Array(raws.prefix(sampleLimit))
var extractTimes: [Double] = []
var aspects: [Double] = []
var extractOK = 0
var extractFail = 0
var portrait = 0
var landscape = 0
var sharpness: [(String, Double)] = []

for url in sample {
    if let (img, ms) = thumbnail(from: url, maxPixel: 512) {
        extractOK += 1
        extractTimes.append(ms)
        let a = Double(img.width) / Double(max(img.height, 1))
        aspects.append(a)
        if a < 0.95 { portrait += 1 } else { landscape += 1 }
        let dest = workDir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".jpg")
        if let destCG = CGImageDestinationCreateWithURL(dest as CFURL, "public.jpeg" as CFString, 1, nil) {
            CGImageDestinationAddImage(destCG, img, nil)
            _ = CGImageDestinationFinalize(destCG)
        }
        sharpness.append((url.lastPathComponent, laplacianVar(img)))
    } else {
        extractFail += 1
        note("bug", "preview", "Extract failed", url.lastPathComponent)
    }
}

let medianAspect = percentile(aspects, p: 0.5)
let aspectOutliers = aspects.filter { abs($0 - medianAspect) / max(medianAspect, 0.01) > 0.35 }.count

if extractFail > 0 {
    note("bug", "preview", "Preview extraction failures", "\(extractFail)/\(sample.count) failed ImageIO thumbnail")
} else {
    note("pass", "preview", "Preview extract OK", "\(extractOK)/\(sample.count) thumbs in sample")
}

if aspectOutliers > sample.count / 4 {
    note("friction", "preview", "Mixed orientations in sample", "\(aspectOutliers) aspect outliers vs median \(String(format: "%.2f", medianAspect)) — wipe compare needs letterboxing (already patched) and group UI should say portrait vs landscape")
} else {
    note("pass", "preview", "Aspect distribution stable", "median \(String(format: "%.2f", medianAspect)), outliers \(aspectOutliers)")
}

let p50 = percentile(extractTimes, p: 0.5)
let p95 = percentile(extractTimes, p: 0.95)
if p95 > 800 {
    note("friction", "import", "Slow preview extract", String(format: "p95 %.0fms per file at 512px — 94 files ≈ %.1fs just for thumbs", p95, p95 * 94 / 1000))
} else {
    note("pass", "import", "Preview latency acceptable", String(format: "p50 %.0fms · p95 %.0fms", p50, p95))
}

// Burst guess from EXIF dates
let dates = parseDates(rawFolder)
let sortedDates = dates.values.sorted()
var bursts = 0
if sortedDates.count > 1 {
    var prev = sortedDates[0]
    var inBurst = false
    for d in sortedDates.dropFirst() {
        if d.timeIntervalSince(prev) <= 2.0 {
            if !inBurst { bursts += 1; inBurst = true }
        } else {
            inBurst = false
        }
        prev = d
    }
}
if dates.isEmpty {
    note("friction", "import", "No EXIF dates via exiftool", "Burst grouping will degrade to filename order / file mtime")
} else {
    note("pass", "cull", "EXIF dates present", "\(dates.count) dated files · ~\(bursts) multi-frame bursts (≤2s gap)")
}

// Taste Kelvin audit
let kelvins = tasteKelvins(jpgFolder)
let extremeK = kelvins.filter { $0 < 2500 || $0 > 10000 }.count
if kelvins.isEmpty {
    note("friction", "taste", "No crs ColorTemperature on JPGs", "Taste retrieval will fall back to baseline — edits look flat")
} else {
    let meanK = kelvins.reduce(0, +) / Double(kelvins.count)
    note("pass", "taste", "Taste library has Kelvin", String(format: "n=%d · min=%.0f · mean=%.0f · max=%.0f", kelvins.count, kelvins.min()!, meanK, kelvins.max()!))
    if extremeK > 0 {
        note("bug", "taste", "Extreme Kelvin in library", "\(extremeK) files outside 2500–10000K — clamp on ingest")
    }
    // Simulate old bug: neutral 6500 + mean
    let buggy = 6500 + meanK
    if buggy > 9000 {
        note("pass", "taste", "Confirmed old Kelvin double-count would distort", String(format: "6500+mean ≈ %.0fK (now fixed by averaging from 0)", buggy))
    }
}

// Sharpness spread — cull signal quality
let sharpVals = sharpness.map(\.1).sorted()
if let lo = sharpVals.first, let hi = sharpVals.last, hi > 0 {
    let ratio = hi / max(lo, 1e-6)
    if ratio < 2 {
        note("friction", "cull", "Weak sharpness separation", String(format: "max/min laplacian ≈ %.1f on thumbs — blur scorer may struggle to rank bursts", ratio))
    } else {
        note("pass", "cull", "Sharpness dynamic range OK", String(format: "laplacian span %.1f× on sample", ratio))
    }
    let soft = sharpness.filter { $0.1 < sharpVals[sharpVals.count / 5] }.prefix(3).map(\.0)
    note("frontier", "cull", "Softest in sample (reject candidates)", soft.joined(separator: ", "))
}

// Scale projection
let fullExtractEstimate = p95 * Double(raws.count) / 1000.0
if fullExtractEstimate > 30 {
    note("friction", "import", "Full-roll extract feels long", String(format: "Est. %.0fs for %d files at p95 — need progressive grid (exists) + cancel button (missing)", fullExtractEstimate, raws.count))
}

// Synthetic UX contract checks (code-level expectations)
note("bug", "ux", "Import flashes Grid then Clusters", "photosReady sets viewMode=.grid; finished sets .cluster — user sees a mode flash mid-import")
note("bug", "ux", "NSEvent monitor leaks", "ContentView onAppear adds local key monitor every appear without removal — stacked handlers")
note("bug", "export", "Manual picks may not export", "draftCollections keeps only isBurstHero||isClusterHero — multi-pick set can lose non-hero keeps")
note("friction", "ux", "Taste folder alert every import", "Modal interrupt before every roll — should remember last taste library / Skip default")
note("friction", "ux", "Meet→Pick→Decide then Uncertain orphaned", "Landing is Clusters; Uncertain badge still high but not the home after pick")
note("friction", "ux", "Grid reloadData on every state tick", "NSCollectionView full reload drops scroll + selection feel during progressive import")
note("friction", "compare", "Wipe uses undeveloped proxies", "ComparePairView loads disk JPEG; SoftPreview applies taste — Space/wipe vs graded preview disagree")
note("frontier", "ux", "Voice of the group", "Replace label 'scene ×6' with captioned story: who/what/when from faces + time + optional VLM one-liner")
note("frontier", "ux", "Pick-set confidence ghost", "Show model’s suggested picks as translucent ghosts under your taps — teach without forcing")
note("frontier", "ux", "Decision budget runway", "Progress ring: decisions left vs estimated minutes; celebrate when a group clears")
note("frontier", "ux", "Spatial morph on sort", "Animate thumb positions when switching Sharpest↔Similar — trust that the model reorganized")
note("frontier", "taste", "Holdout score in UI", "After taste apply, show ‘look match 0.82 vs your Mehendi edits’ per photo")

let metrics = Metrics(
    rawCount: raws.count,
    jpgCount: jpgs.count,
    sampleSize: sample.count,
    extractOK: extractOK,
    extractFail: extractFail,
    aspectOutliers: aspectOutliers,
    medianAspect: medianAspect,
    extractP50ms: p50,
    extractP95ms: p95,
    tasteFilesWithCRS: kelvins.count,
    tasteKelvinMin: kelvins.min(),
    tasteKelvinMax: kelvins.max(),
    tasteKelvinMean: kelvins.isEmpty ? nil : kelvins.reduce(0, +) / Double(kelvins.count),
    extremeKelvinCount: extremeK,
    portraitCount: portrait,
    landscapeCount: landscape,
    burstGuessCount: bursts,
    exiftoolAvailable: FileManager.default.isExecutableFile(atPath: "/usr/local/bin/exiftool")
)

let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("DerivedData/e2e")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let reportURL = outDir.appendingPathComponent("report.json")
let payload: [String: Any] = [
    "generatedAt": ISO8601DateFormatter().string(from: Date()),
    "metrics": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(metrics)),
    "findings": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(findings)),
]
let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
try data.write(to: reportURL)
print("\nWrote \(reportURL.path)")
print("Summary: \(findings.filter{$0.severity=="bug"}.count) bugs · \(findings.filter{$0.severity=="friction"}.count) friction · \(findings.filter{$0.severity=="frontier"}.count) frontier · \(findings.filter{$0.severity=="pass"}.count) pass")
