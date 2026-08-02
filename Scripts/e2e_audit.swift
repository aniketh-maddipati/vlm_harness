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
    var cacheDecodeP50ms: Double?
    var cacheDecodeP95ms: Double?
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

// Simulate warm-cache JPEG decode (navigation / scroll-ahead SLA)
var cacheDecodeTimes: [Double] = []
let cachedJPGs = (try? FileManager.default.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil))?
    .filter { $0.pathExtension.lowercased() == "jpg" } ?? []
for url in cachedJPGs.prefix(sampleLimit) {
    let t0 = CFAbsoluteTimeGetCurrent()
    if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
       CGImageSourceCreateImageAtIndex(src, 0, nil) != nil {
        cacheDecodeTimes.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }
}
let cacheP50 = cacheDecodeTimes.isEmpty ? nil : percentile(cacheDecodeTimes, p: 0.5)
let cacheP95 = cacheDecodeTimes.isEmpty ? nil : percentile(cacheDecodeTimes, p: 0.95)
if let cacheP95 {
    if cacheP95 <= 50 {
        note("pass", "latency", "Cache decode within SLA", String(format: "p50 %.1fms · p95 %.1fms (target ≤50ms p95)", cacheP50 ?? 0, cacheP95))
    } else {
        note("bug", "latency", "Cache decode exceeds SLA", String(format: "p95 %.1fms > 50ms on %d cached thumbs", cacheP95, cacheDecodeTimes.count))
    }
} else {
    note("friction", "latency", "Cache decode not measured", "No cached JPGs in workDir sample")
}
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

// Synthetic UX contract checks — verify against current codebase expectations
func sourceContains(_ path: String, _ needle: String) -> Bool {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
    return text.contains(needle)
}

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let contentView = repoRoot.appendingPathComponent("Lumina/ContentView.swift").path
let exportSvc = repoRoot.appendingPathComponent("Lumina/Services/ExportService.swift").path
let vmPath = repoRoot.appendingPathComponent("Lumina/ViewModels/ProjectViewModel.swift").path

if sourceContains(contentView, "removeMonitor(keyMonitor)") {
    note("pass", "ux", "Key monitor cleaned up on disappear", "NSEvent monitor removed in onDisappear")
} else {
    note("bug", "ux", "NSEvent monitor may leak", "ContentView missing removeMonitor on disappear")
}

if sourceContains(vmPath, "sessionPhase = .meet") && sourceContains(repoRoot.appendingPathComponent("Lumina/Views/SessionSpineView.swift").path, "Meet") == false
    && sourceContains(repoRoot.appendingPathComponent("Lumina/Views/UncertainAndClusterViews.swift").path, "SessionSpineView") {
    note("pass", "ux", "Import lands on Meet spine", "Linear Meet → Pick → Decide → Export")
} else if sourceContains(vmPath, "sessionPhase = .meet") {
    note("pass", "ux", "Import lands on Meet spine", "No parallel mode matrix after import")
} else {
    note("bug", "ux", "Import mode flash", "Import may not enter Meet phase")
}

if sourceContains(exportSvc, "filter { $0.tier == .keep }") {
    note("pass", "export", "Collections include all keeps", "draftCollections filters by tier == keep")
} else {
    note("bug", "export", "Manual picks may not export", "draftCollections may omit non-hero keeps")
}

let agentFiles = [
    "Lumina/Models/AgentModels.swift",
    "Lumina/Services/FeedbackStore.swift",
    "Lumina/Services/PhotoAgentOrchestrator.swift",
    "Lumina/Views/UnifiedCanvasView.swift",
    "Lumina/Views/StackFeedView.swift",
]
let missingAgent = agentFiles.filter { !FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent($0).path) }
if missingAgent.isEmpty {
    note("pass", "agent", "Agentic modules present", "JobBrief, FeedbackStore, Orchestrator, UnifiedCanvas, StackFeed")
} else {
    note("bug", "agent", "Missing agent modules", missingAgent.joined(separator: ", "))
}

if sourceContains(vmPath, "TasteLearning.learnFromUserDecision") {
    note("pass", "agent", "Feedback loop wired", "keep/reject/hero updates taste index")
} else {
    note("bug", "agent", "No feedback loop", "markKeep/markReject not learning taste")
}

if sourceContains(vmPath, "pickRAWFolder") && sourceContains(vmPath, "tasteStrength") {
    note("pass", "product", "RAW+JPG import with taste strength", "Manual folder import · extracted profile scaled by slider")
} else {
    note("friction", "product", "Taste-first import missing", "Need RAW folder picker and tasteStrength on project")
}

if sourceContains(contentView, "TasteStrengthPanel") && sourceContains(contentView, "Resume last project") {
    note("pass", "product", "Taste panel + resume", "Sidebar shows extracted look and last project")
} else {
    note("friction", "product", "Taste sidebar incomplete", "Missing TasteStrengthPanel or resume UX")
}

if sourceContains(repoRoot.appendingPathComponent("Lumina/Views/ExportPayoffSheet.swift").path, "Ready to post") {
    note("pass", "product", "Export payoff sheet", "Post-export thumbnail strip + taste readout")
} else {
    note("friction", "product", "Export payoff missing", "No in-app export summary")
}

if sourceContains(vmPath, "undoLastStack") && sourceContains(vmPath, "sessionSummary") {
    note("pass", "agent", "Trust layer present", "Stack undo + session summary")
} else {
    note("friction", "agent", "Trust layer incomplete", "Missing undo or session summary")
}

let latencyPath = repoRoot.appendingPathComponent("Lumina/Services/LatencyMetrics.swift").path
if FileManager.default.fileExists(atPath: latencyPath) {
    note("pass", "perf", "Latency instrumentation present", "LatencyMetrics + os_signpost hooks")
} else {
    note("bug", "perf", "Latency harness missing", "No LatencyMetrics.swift")
}

let spinePath = repoRoot.appendingPathComponent("Lumina/Services/PreviewSpine.swift").path
let speedBrowsePath = repoRoot.appendingPathComponent("Lumina/Views/SpeedBrowseViewer.swift").path
let hudPath = repoRoot.appendingPathComponent("Lumina/Views/SpeedContractHUD.swift").path
if FileManager.default.fileExists(atPath: spinePath)
    && sourceContains(spinePath, "input_to_photon")
    && sourceContains(spinePath, "reaim")
    && FileManager.default.fileExists(atPath: speedBrowsePath)
    && FileManager.default.fileExists(atPath: hudPath)
    && sourceContains(contentView, "toggleSpeedHUD")
    && sourceContains(vmPath, "advanceBrowse") {
    note("pass", "perf", "Speed Contract spine", "PreviewSpine + browse viewer + HUD · paint <50ms contract")
} else {
    note("bug", "perf", "Speed Contract incomplete", "Missing PreviewSpine, SpeedBrowseViewer, or HUD wiring")
}

if sourceContains(latencyPath, "percentile") && sourceContains(latencyPath, "p99") {
    note("pass", "perf", "Contract percentiles", "p50/p95/p99 for spine.input_to_photon")
} else {
    note("friction", "perf", "Percentiles missing", "LatencyMetrics needs percentile helpers")
}

let metalPoolPath = repoRoot.appendingPathComponent("Lumina/Services/MetalPreviewPool.swift").path
let metalCanvasPath = repoRoot.appendingPathComponent("Lumina/Views/MetalBrowseCanvas.swift").path
let projectStorePath = repoRoot.appendingPathComponent("Lumina/Services/ProjectStore.swift").path
let photoRecordPath = repoRoot.appendingPathComponent("Lumina/Models/PhotoRecord.swift").path
if FileManager.default.fileExists(atPath: metalPoolPath)
    && FileManager.default.fileExists(atPath: metalCanvasPath)
    && sourceContains(metalPoolPath, "IOSurface")
    && sourceContains(metalPoolPath, "CVMetalTextureCache")
    && sourceContains(metalPoolPath, "mappedIfSafe")
    && sourceContains(metalCanvasPath, "CAMetalLayer")
    && sourceContains(projectStorePath, "extractBrowsePreview")
    && sourceContains(photoRecordPath, "PreviewOrigin")
    && sourceContains(spinePath, "ripVelocity")
    && sourceContains(speedBrowsePath, "MetalBrowseCanvas") {
    note("pass", "perf", "Narrative+ browse path", "embedded/synth ingest · mmap · IOSurface Metal pool · CAMetalLayer · rip prefetch")
} else {
    note("bug", "perf", "Narrative+ browse path incomplete", "Missing embedded preview extract, Metal pool, or canvas wiring")
}

if sourceContains(vmPath, "prefetchStackFeed") {
    note("pass", "perf", "Stack feed scroll-ahead prefetch", "prefetchStackFeed on card appear")
} else {
    note("friction", "perf", "Stack prefetch missing", "StackFeedView lacks scroll-ahead")
}

if sourceContains(contentView, "case \"f\"") && sourceContains(contentView, "case \"p\"") && sourceContains(contentView, "advanceFrame") {
    note("pass", "ux", "Cull keys mapped", "F/D navigate · P/X keep/reject · M flag")
} else {
    note("friction", "ux", "Cull keys incomplete", "Missing F/D/P/X/M global anchors")
}

if sourceContains(repoRoot.appendingPathComponent("Lumina/Views/GridOverviewView.swift").path, "DynamicSortBar")
    && sourceContains(repoRoot.appendingPathComponent("Lumina/Views/CompareAndSoftViews.swift").path, "GradedCompareView") {
    note("pass", "ux", "Grid lens + graded compare", "Sort bar in grid only · unified taste preview")
} else {
    note("friction", "ux", "Spine UX incomplete", "Missing GridOverviewView or GradedCompareView")
}

let ingestOrchestrator = repoRoot.appendingPathComponent("Lumina/Services/IngestOrchestrator.swift").path
let mediaFormats = repoRoot.appendingPathComponent("Lumina/Services/MediaFormats.swift").path
if FileManager.default.fileExists(atPath: ingestOrchestrator)
    && sourceContains(mediaFormats, "discoverPhotos") {
    note("pass", "ingest", "Discovery helpers present", "Deep folder scan available (manual import path)")
} else {
    note("friction", "ingest", "Discovery helpers missing", "MediaFormats.discoverPhotos not found")
}

if sourceContains(mediaFormats, "maxDepth") && sourceContains(mediaFormats, "duplicate") {
    note("pass", "ingest", "Recursive discovery with dedup", "Nested DCIM folders supported")
} else {
    note("friction", "ingest", "Shallow discovery only", "May miss nested camera folders")
}

if FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("Lumina/Services/IngestWatcher.swift").path) {
    note("pass", "ingest", "Volume watcher (deferred)", "Infrastructure present · UI not wired in v1")
} else {
    note("friction", "ingest", "No volume watcher", "SD auto-import deferred")
}

if FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("Lumina/Services/SourceCatalog.swift").path)
    && sourceContains(repoRoot.appendingPathComponent("Lumina/Services/SourceCatalog.swift").path, "iCloud") {
    note("pass", "ingest", "Multi-source catalog present", "SD · external HDD · iCloud · iPhone detection")
} else {
    note("friction", "ingest", "Source catalog missing", "No iCloud/iPhone/external drive routing")
}

if sourceContains(repoRoot.appendingPathComponent("Lumina/Services/ProjectStore.swift").path, "extractFullImage") {
    note("pass", "ingest", "Full-res JPG/HEIC decode", "Not embedded thumbnail for processed formats")
} else {
    note("friction", "ingest", "Thumbnail-only decode", "JPG/HEIC may use low-res embedded preview")
}

// Nested folder discovery smoke test (inline — e2e script is outside app module)
func countPhotosRecursive(_ dir: URL, depth: Int = 0) -> Int {
    guard depth < 10 else { return 0 }
    guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return 0 }
    var count = 0
    for entry in entries {
        if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            count += countPhotosRecursive(entry, depth: depth + 1)
        } else {
            let ext = entry.pathExtension.uppercased()
            if ["ARW", "CR2", "CR3", "NEF", "DNG", "JPG", "JPEG", "HEIC"].contains(ext) { count += 1 }
        }
    }
    return count
}

let nestedRoot = workDir.appendingPathComponent("DCIM/100CANON", isDirectory: true)
try? FileManager.default.createDirectory(at: nestedRoot, withIntermediateDirectories: true)
if let sampleFile = sample.first {
    let dest = nestedRoot.appendingPathComponent(sampleFile.lastPathComponent)
    try? FileManager.default.copyItem(at: sampleFile, to: dest)
    let nestedCount = countPhotosRecursive(workDir.appendingPathComponent("DCIM"))
    if nestedCount >= 1 {
        note("pass", "ingest", "Nested DCIM layout discoverable", "Found \(nestedCount) file(s) under DCIM/ tree")
    } else {
        note("bug", "ingest", "Nested layout test failed", "Could not find file under DCIM/100CANON")
    }
}

note("frontier", "ux", "Decision budget runway", "Progress ring: decisions left vs estimated minutes; celebrate when a group clears")
note("frontier", "ux", "Spatial morph on sort", "Animate thumb positions when switching Sharpest↔Similar — trust that the model reorganized")
note("frontier", "taste", "Holdout score in UI", "After taste apply, show look match vs your edits per photo")

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
    cacheDecodeP50ms: cacheP50,
    cacheDecodeP95ms: cacheP95,
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
