#!/usr/bin/env swift
/**
 Headless P0 contact-sheet timing harness.
 Measures folder→first catalog, first embedded preview, and memory during preparation.

 Usage:
   swift Scripts/run/p0_contact_sheet_bench.swift /path/to/arw-folder [limit]

 Writes JSON metrics to DerivedData/p0-contact-sheet/bench.json
 */
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import Darwin

let args = CommandLine.arguments.dropFirst()
guard let folderArg = args.first else {
    fputs("Usage: swift Scripts/run/p0_contact_sheet_bench.swift FOLDER [limit]\n", stderr)
    exit(2)
}
let folder = URL(fileURLWithPath: folderArg)
let limit = args.dropFirst().first.flatMap(Int.init) ?? 220

func rssMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return -1 }
    return Double(info.resident_size) / 1_048_576.0
}

func collectARWs(in root: URL, limit: Int) -> [URL] {
    var out: [URL] = []
    let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
    while let next = enumerator?.nextObject() as? URL {
        if next.pathExtension.uppercased() == "ARW" {
            out.append(next)
            if out.count >= limit { break }
        }
    }
    return out
}

func extractEmbedded(to dest: URL, from source: URL, maxPixel: Int) -> Bool {
    if FileManager.default.fileExists(atPath: dest.path) { return true }
    guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else { return false }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
        kCGImageSourceCreateThumbnailFromImageAlways: false,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
        let synth: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let fallback = CGImageSourceCreateThumbnailAtIndex(src, 0, synth as CFDictionary) else { return false }
        guard let destImg = CGImageDestinationCreateWithURL(dest as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destImg, fallback, nil)
        return CGImageDestinationFinalize(destImg)
    }
    guard let destImg = CGImageDestinationCreateWithURL(dest as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destImg, image, nil)
    return CGImageDestinationFinalize(destImg)
}

let files = collectARWs(in: folder, limit: limit)
guard !files.isEmpty else {
    fputs("No ARW files in \(folder.path)\n", stderr)
    exit(1)
}

let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("DerivedData/p0-contact-sheet", isDirectory: true)
let cacheDir = outDir.appendingPathComponent("cache", isDirectory: true)
try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

let t0 = CFAbsoluteTimeGetCurrent()
let rss0 = rssMB()

// Phase 1: discover + establish stable records (IDs)
struct Rec { let id: UUID; let url: URL }
var records: [Rec] = []
for (i, url) in files.enumerated() {
    let rel = url.path.replacingOccurrences(of: folder.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let key = "bench|\(rel)|\(i)"
    let id = UUID(uuidString: String(format: "%08x-0000-5000-8000-%012x", key.hashValue & 0xffff_ffff, i)) ?? UUID()
    records.append(Rec(id: id, url: url))
}
let discoverMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
let firstPaintMs = discoverMs // catalog ready ⇒ contact sheet can open

// Phase 2: visible window previews first
let visible = min(48, records.count)
var firstPreviewMs: Double?
let previewStart = CFAbsoluteTimeGetCurrent()
var ready = 0
for rec in records.prefix(visible) {
    let dest = cacheDir.appendingPathComponent(rec.id.uuidString.lowercased() + ".jpg")
    if extractEmbedded(to: dest, from: rec.url, maxPixel: 1200) {
        ready += 1
        if firstPreviewMs == nil {
            firstPreviewMs = (CFAbsoluteTimeGetCurrent() - previewStart) * 1000
        }
    }
}
let visiblePreviewMs = (CFAbsoluteTimeGetCurrent() - previewStart) * 1000

// Phase 3: remaining background (bounded concurrency)
let bgStart = CFAbsoluteTimeGetCurrent()
let rest = Array(records.dropFirst(visible))
let group = DispatchGroup()
let sem = DispatchSemaphore(value: 8)
for rec in rest {
    group.enter()
    sem.wait()
    DispatchQueue.global(qos: .utility).async {
        defer { sem.signal(); group.leave() }
        let dest = cacheDir.appendingPathComponent(rec.id.uuidString.lowercased() + ".jpg")
        _ = extractEmbedded(to: dest, from: rec.url, maxPixel: 1200)
    }
}
group.wait()
let backgroundMs = (CFAbsoluteTimeGetCurrent() - bgStart) * 1000
let totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
let rss1 = rssMB()

let metrics: [String: Any] = [
    "folder": folder.path,
    "assetCount": records.count,
    "discoverToCatalogMs": discoverMs,
    "folderToFirstPaintMs": firstPaintMs,
    "firstUsablePreviewMs": firstPreviewMs as Any,
    "visibleWindowPreviewMs": visiblePreviewMs,
    "backgroundRemainingMs": backgroundMs,
    "totalPreparationMs": totalMs,
    "rssStartMB": rss0,
    "rssEndMB": rss1,
    "rssDeltaMB": rss1 - rss0,
    "visiblePreviewReady": ready,
]

let json = try! JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
let reportURL = outDir.appendingPathComponent("bench.json")
try! json.write(to: reportURL)
FileHandle.standardOutput.write(json)
print("")
print("Wrote \(reportURL.path)")
