#!/usr/bin/env swift
/**
 E1 Gate 3 — decode-floor baseline over a cut latency card.

 Measures the per-frame work the contact sheet performs while it scrolls: an
 embedded-preview decode at `PhotoImageTier.gridMaxPixelSize` (512 px), which is
 what `PhotoImageCache.load` asks ImageIO for on the grid tier.

 What this IS: the decode floor of the current engine, over EVERY frame in the
 fixture — full-run percentiles, in the spirit of `LatencyMetrics` capture mode.
 What this IS NOT: `scroll.frame`. It does not include SwiftUI layout, cell
 reuse, compositing, or display-link pacing, and no key is named `scroll.frame`
 anywhere in the app yet. A number from here must not be reported as a frame time.

 Usage:
   swift Scripts/perf/e1_decode_baseline.swift <fixture-dir> [--json out.json]

 Nothing is written into the fixture directory.
 */
import Foundation
import ImageIO
import CoreGraphics
import Darwin

let gridMaxPixelSize = 512  // mirrors PhotoImageTier.gridMaxPixelSize

var args = Array(CommandLine.arguments.dropFirst())
guard let folderArg = args.first else {
    fputs("Usage: swift Scripts/perf/e1_decode_baseline.swift FIXTURE_DIR [--json OUT]\n", stderr)
    exit(2)
}
let folder = URL(fileURLWithPath: folderArg)
var jsonOut: URL?
if let i = args.firstIndex(of: "--json"), args.indices.contains(i + 1) {
    jsonOut = URL(fileURLWithPath: args[i + 1])
}

func rssBytes() -> Int {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int(info.resident_size) : -1
}

let rawExtensions: Set<String> = ["ARW", "CR3", "NEF", "RAF", "DNG", "HEIC"]
var frames: [URL] = []
if let entries = try? FileManager.default.contentsOfDirectory(
    at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
    frames = entries
        .filter { rawExtensions.contains($0.pathExtension.uppercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}
guard !frames.isEmpty else {
    fputs("No RAW frames in \(folder.path)\n", stderr)
    exit(1)
}

/// One embedded-preview decode at the grid tier. Returns elapsed ms, or nil on failure.
func decodeOnce(_ url: URL) -> Double? {
    let start = CFAbsoluteTimeGetCurrent()
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
        kCGImageSourceCreateThumbnailFromImageAlways: false,
        kCGImageSourceThumbnailMaxPixelSize: gridMaxPixelSize,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) != nil else { return nil }
    return (CFAbsoluteTimeGetCurrent() - start) * 1000
}

var samples: [Double] = []
samples.reserveCapacity(frames.count)
var failures = 0
var peakRSS = rssBytes()
let rss0 = peakRSS
let runStart = CFAbsoluteTimeGetCurrent()

for (i, url) in frames.enumerated() {
    if let ms = decodeOnce(url) { samples.append(ms) } else { failures += 1 }
    let rss = rssBytes()
    if rss > peakRSS { peakRSS = rss }
    if (i + 1) % 250 == 0 {
        FileHandle.standardError.write("  \(i + 1)/\(frames.count)\n".data(using: .utf8)!)
    }
}
let wallMs = (CFAbsoluteTimeGetCurrent() - runStart) * 1000

func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    let clamped = min(max(p, 0), 1)
    let idx = min(Int(Double(sorted.count - 1) * clamped), sorted.count - 1)
    return sorted[idx]
}
let sorted = samples.sorted()
let p50 = percentile(sorted, 0.50)
let p95 = percentile(sorted, 0.95)
let p99 = percentile(sorted, 0.99)
let maxMs = sorted.last ?? .nan
let mean = samples.reduce(0, +) / Double(max(samples.count, 1))

// Coverage is full-run by construction: every frame the fixture holds was decoded
// once and every sample is in the percentile. Nothing was windowed away.
let declaration = "n=\(samples.count), full run"

// What the OLD instrument would have reported: LatencyMetrics kept a 512-sample
// ring per key, so a run longer than that described only its tail. Computing both
// here shows the Gate 1 fix against real decode data rather than a synthetic spike.
let ringCapacity = 512
let tail = samples.count > ringCapacity ? Array(samples.suffix(ringCapacity)) : samples
let tailSorted = tail.sorted()
let tailP99 = percentile(tailSorted, 0.99)
let tailMax = tailSorted.last ?? .nan
let tailDeclaration = samples.count > ringCapacity
    ? "n=\(tail.count), tail (of \(samples.count) recorded)"
    : "n=\(tail.count), full run"
let maxIndex = samples.firstIndex(of: maxMs) ?? -1

let report = """
fixture:        \(folder.lastPathComponent)
frames on disk: \(frames.count)
decoded ok:     \(samples.count)   failures: \(failures)
window:         \(declaration)
decode ms       p50=\(String(format: "%.2f", p50))  p95=\(String(format: "%.2f", p95))  \
p99=\(String(format: "%.2f", p99))  max=\(String(format: "%.2f", maxMs))  \
mean=\(String(format: "%.2f", mean))
wall            \(String(format: "%.1f", wallMs / 1000)) s
rss             start=\(rss0 / 1_048_576) MB  peak=\(peakRSS / 1_048_576) MB
slowest frame   \(String(format: "%.2f", maxMs)) ms at sample #\(maxIndex)
ring would say  p99=\(String(format: "%.2f", tailP99))  max=\(String(format: "%.2f", tailMax))  [\(tailDeclaration)]
"""
print(report)

if let jsonOut {
    let payload: [String: Any] = [
        "fixture": folder.lastPathComponent,
        "metric": "decode.grid_512",
        "what_it_measures": "embedded-preview decode at PhotoImageTier.gridMaxPixelSize (512 px)",
        "what_it_is_not": "scroll.frame — excludes SwiftUI layout, cell reuse, compositing, display-link pacing",
        "frames_on_disk": frames.count,
        "sample_count": samples.count,
        "decode_failures": failures,
        "coverage": "full run",
        "window_declaration": declaration,
        "p50_ms": p50, "p95_ms": p95, "p99_ms": p99, "max_ms": maxMs, "mean_ms": mean,
        "wall_seconds": wallMs / 1000,
        "rss_start_bytes": rss0,
        "rss_peak_bytes": peakRSS,
        "max_sample_index": maxIndex,
        "ring512_p99_ms": tailP99,
        "ring512_max_ms": tailMax,
        "ring512_window_declaration": tailDeclaration,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: jsonOut)
        FileHandle.standardError.write("wrote \(jsonOut.path)\n".data(using: .utf8)!)
    }
}
