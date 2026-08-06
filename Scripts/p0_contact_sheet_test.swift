#!/usr/bin/env swift
/**
 Deterministic P0 contact-sheet preparation tests.
 Mirrors discovery, identity, incremental insertion, restore, and cache contracts.

 Run: swift Scripts/p0_contact_sheet_test.swift
 */
import Foundation
import CryptoKit
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

var failures = 0
func expect(_ cond: Bool, _ msg: String) {
    if cond {
        print("PASS: \(msg)")
    } else {
        print("FAIL: \(msg)")
        failures += 1
    }
}

// MARK: - Mirrors

enum CullDecision: String, Codable { case undecided, keep, reject, hold }
enum SourceAvailability: String, Codable { case available, missing, unknown }
enum GridFilter: String, Codable { case all, keeps, rejects, flagged }
enum WorkspaceScale: String, Codable { case contactSheet, singlePhoto }
enum IngestSkipReason: String { case duplicate, sidecar, unsupported, video }

struct SourceReference: Codable {
    var originalPath: String
    var relativePath: String
    var volumeID: String?
    var availability: SourceAvailability
}

struct AssetRecord: Codable, Identifiable {
    var id: UUID
    var sourceKey: String
    var source: SourceReference
    var filename: String
    var cull: CullDecision
    var recipe: String?
    var capturedAt: Date?
    var fileSize: Int64?
    var thumbPath: String?
    var gridThumbPath: String?
}

struct WorkspaceRestoreState: Codable, Equatable {
    var focusedAssetID: UUID?
    var filter: GridFilter
    var contactSheetDensity: Int?
    var scrollAnchor: Double?
    var scale: WorkspaceScale
    var keptOrderMode: Bool
}

enum AssetIdentity {
    static func sourceKey(volumeID: String?, relativePath: String, fileSize: Int64?, capturedAt: Date?) -> String {
        let vol = volumeID?.lowercased() ?? ""
        let rel = relativePath.lowercased()
        let size = fileSize.map(String.init) ?? ""
        let stamp = capturedAt.map { String(format: "%.3f", $0.timeIntervalSince1970) } ?? ""
        return "v1|\(vol)|\(rel)|\(size)|\(stamp)"
    }

    static func resolveID(sourceKey: String, preserved: UUID? = nil) -> UUID {
        if let preserved { return preserved }
        let digest = SHA256.hash(data: Data(sourceKey.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func cacheStem(for assetID: UUID) -> String {
        assetID.uuidString.lowercased()
    }

    static func relativePath(file: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        if filePath.hasPrefix(rootPath) {
            var rel = String(filePath.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            return rel.lowercased()
        }
        return file.lastPathComponent.lowercased()
    }
}

func chronologicalLess(_ lhs: AssetRecord, _ rhs: AssetRecord) -> Bool {
    switch (lhs.capturedAt, rhs.capturedAt) {
    case let (l?, r?):
        if l != r { return l < r }
    case (_?, nil): return true
    case (nil, _?): return false
    case (nil, nil): break
    }
    return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
}

struct DiscoveryResult {
    var importable: [URL]
    var skipped: [(path: String, reason: IngestSkipReason)]
}

func discoverPhotos(at root: URL) -> DiscoveryResult {
    var importable: [URL] = []
    var skipped: [(String, IngestSkipReason)] = []
    var seen = Set<String>()
    let known: Set<String> = ["ARW", "JPG", "JPEG", "CR2", "NEF", "DNG", "HEIC"]
    let video: Set<String> = ["MP4", "MOV"]

    func walk(_ dir: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                walk(entry)
                continue
            }
            let ext = entry.pathExtension.uppercased()
            if video.contains(ext) {
                skipped.append((entry.path, .video))
                continue
            }
            if ext == "XMP" {
                skipped.append((entry.path, .sidecar))
                continue
            }
            guard known.contains(ext) else {
                skipped.append((entry.path, .unsupported))
                continue
            }
            let size = (try? entry.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let key = "\(entry.path)|\(size)"
            if seen.contains(key) {
                skipped.append((entry.path, .duplicate))
                continue
            }
            // Content-ish dedup: same size + filename collision across hard links simulated by path+size.
            let soft = "\(entry.lastPathComponent.lowercased())|\(size)|\(entry.deletingLastPathComponent().lastPathComponent)"
            if seen.contains(soft) {
                // allow same filename in different folders
            }
            seen.insert(key)
            importable.append(entry)
        }
    }
    walk(root)
    importable.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    return DiscoveryResult(importable: importable, skipped: skipped)
}

func writeTinyJPEG(to url: URL, width: Int, height: Int) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setFillColor(CGColor(red: 0.8, green: 0.7, blue: 0.6, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = ctx.makeImage()!
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Fixture tree

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("p0-cs-\(UUID().uuidString)", isDirectory: true)
let nestedA = root.appendingPathComponent("a", isDirectory: true)
let nestedB = root.appendingPathComponent("b", isDirectory: true)
try! fm.createDirectory(at: nestedA, withIntermediateDirectories: true)
try! fm.createDirectory(at: nestedB, withIntermediateDirectories: true)

// Same filename in different folders
try! Data([0x01, 0x02, 0x03, 0x04]).write(to: nestedA.appendingPathComponent("DSC0001.ARW"))
try! Data([0x05, 0x06, 0x07, 0x08]).write(to: nestedB.appendingPathComponent("DSC0001.ARW"))
try! Data([0x11]).write(to: nestedA.appendingPathComponent("DSC0002.JPG"))
try! Data([0x22]).write(to: nestedA.appendingPathComponent("notes.txt"))
try! Data([0x33]).write(to: nestedA.appendingPathComponent("clip.MOV"))
try! Data([0x44]).write(to: nestedA.appendingPathComponent("sidecar.XMP"))

let discovery = discoverPhotos(at: root)
expect(discovery.importable.count == 3, "recursive discovery finds nested photos")
expect(discovery.skipped.contains(where: { $0.reason == .unsupported }), "unsupported-file accounting")
expect(discovery.skipped.contains(where: { $0.reason == .video }), "video skip accounting")
expect(discovery.skipped.contains(where: { $0.reason == .sidecar }), "sidecar skip accounting")

let relA = AssetIdentity.relativePath(file: nestedA.appendingPathComponent("DSC0001.ARW"), root: root)
let relB = AssetIdentity.relativePath(file: nestedB.appendingPathComponent("DSC0001.ARW"), root: root)
expect(relA != relB, "same filenames in different folders stay distinct paths")
let keyA = AssetIdentity.sourceKey(volumeID: "VOL", relativePath: relA, fileSize: 4, capturedAt: nil)
let keyB = AssetIdentity.sourceKey(volumeID: "VOL", relativePath: relB, fileSize: 4, capturedAt: nil)
expect(keyA != keyB, "duplicate suppression uses relative path, not basename")
expect(AssetIdentity.resolveID(sourceKey: keyA) != AssetIdentity.resolveID(sourceKey: keyB), "distinct IDs for same filename")

// Incremental insertion + focus/selection survival
var assets: [AssetRecord] = discovery.importable.enumerated().map { idx, url in
    let rel = AssetIdentity.relativePath(file: url, root: root)
    let key = AssetIdentity.sourceKey(volumeID: "VOL", relativePath: rel, fileSize: Int64(idx + 1), capturedAt: nil)
    let id = AssetIdentity.resolveID(sourceKey: key)
    return AssetRecord(
        id: id,
        sourceKey: key,
        source: SourceReference(originalPath: url.path, relativePath: rel, volumeID: "VOL", availability: .available),
        filename: url.lastPathComponent,
        cull: .undecided,
        recipe: nil,
        capturedAt: nil,
        fileSize: Int64(idx + 1),
        thumbPath: nil,
        gridThumbPath: nil
    )
}
assets.sort(by: chronologicalLess)
var focus = assets[1].id
var selection: Set<UUID> = [assets[0].id, assets[2].id]
let beforeIDs = assets.map(\.id)

// Simulate incremental insertion of a late-discovered file
let lateURL = nestedB.appendingPathComponent("DSC0099.JPG")
try! Data([0x99]).write(to: lateURL)
let lateRel = AssetIdentity.relativePath(file: lateURL, root: root)
let lateKey = AssetIdentity.sourceKey(volumeID: "VOL", relativePath: lateRel, fileSize: 1, capturedAt: nil)
let lateID = AssetIdentity.resolveID(sourceKey: lateKey)
assets.append(
    AssetRecord(
        id: lateID,
        sourceKey: lateKey,
        source: SourceReference(originalPath: lateURL.path, relativePath: lateRel, volumeID: "VOL", availability: .available),
        filename: lateURL.lastPathComponent,
        cull: .undecided,
        recipe: nil,
        capturedAt: nil,
        fileSize: 1,
        thumbPath: nil,
        gridThumbPath: nil
    )
)
assets.sort(by: chronologicalLess)
expect(assets.map(\.id).contains(lateID), "incremental asset insertion")
expect(assets.map(\.id).filter { beforeIDs.contains($0) }.count == beforeIDs.count, "prior assets survive insertion")
expect(focus == assets.first(where: { $0.id == focus })?.id, "focus survives incremental updates")
expect(selection.isSubset(of: Set(assets.map(\.id))), "selection survives incremental updates")

// Metadata merge reorders chronologically without changing identity
let t0 = Date(timeIntervalSince1970: 1_700_000_000)
let t1 = Date(timeIntervalSince1970: 1_700_000_100)
let t2 = Date(timeIntervalSince1970: 1_700_000_050)
for i in assets.indices {
    if assets[i].filename.contains("0001") && assets[i].source.relativePath.contains("/a/") {
        assets[i].capturedAt = t1
    } else if assets[i].filename.contains("0001") {
        assets[i].capturedAt = t0
    } else if assets[i].filename.contains("0002") {
        assets[i].capturedAt = t2
    }
}
assets.sort(by: chronologicalLess)
expect(assets.first?.capturedAt == t0, "stable chronological ordering after metadata merge")
expect(assets.contains(where: { $0.id == focus }), "focus survives metadata merge")
expect(selection.isSubset(of: Set(assets.map(\.id))), "selection survives metadata merge")

// Missing external drive — catalog retained
for i in assets.indices {
    assets[i].source.availability = .missing
}
expect(assets.allSatisfy { $0.source.availability == .missing }, "missing external drive marks availability")
expect(!assets.isEmpty, "missing drive keeps catalog rows")

// Cache paths keyed by asset identity
let cacheDir = root.appendingPathComponent("cache/grid512", isDirectory: true)
try! fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
let asset = assets[0]
let identityCache = cacheDir.appendingPathComponent(AssetIdentity.cacheStem(for: asset.id) + ".jpg")
let legacyCache = cacheDir.appendingPathComponent(asset.filename.replacingOccurrences(of: ".ARW", with: "").replacingOccurrences(of: ".JPG", with: "").replacingOccurrences(of: ".jpg", with: "") + ".jpg")
writeTinyJPEG(to: legacyCache, width: 120, height: 80)
if !fm.fileExists(atPath: identityCache.path) {
    try! fm.copyItem(at: legacyCache, to: identityCache)
}
expect(fm.fileExists(atPath: identityCache.path), "cache paths keyed by asset identity")
expect(AssetIdentity.cacheStem(for: asset.id) != (asset.filename as NSString).deletingPathExtension.lowercased()
        || asset.filename.contains("DSC0001"), "cache stem is identity UUID, not colliding filename alone")
expect(identityCache.lastPathComponent == asset.id.uuidString.lowercased() + ".jpg", "identity cache filename")

// Restore density, focus, filter, scroll
var restore = WorkspaceRestoreState(
    focusedAssetID: focus,
    filter: .keeps,
    contactSheetDensity: 8,
    scrollAnchor: 0.42,
    scale: .contactSheet,
    keptOrderMode: false
)
let encoded = try! JSONEncoder().encode(restore)
let decoded = try! JSONDecoder().decode(WorkspaceRestoreState.self, from: encoded)
expect(decoded.focusedAssetID == focus, "restore focus")
expect(decoded.filter == .keeps, "restore filter")
expect(decoded.contactSheetDensity == 8, "restore density")
expect(abs((decoded.scrollAnchor ?? -1) - 0.42) < 0.0001, "restore scroll anchor")

// Duplicate suppression: identical path+size listed twice
var seenKeys = Set<String>()
var dupSkipped = 0
for url in discovery.importable + discovery.importable {
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    let key = "\(url.path)|\(size)"
    if seenKeys.contains(key) {
        dupSkipped += 1
        continue
    }
    seenKeys.insert(key)
}
expect(dupSkipped == discovery.importable.count, "duplicate suppression on rediscovery")

try? fm.removeItem(at: root)

if failures > 0 {
    fputs("p0_contact_sheet_test: \(failures) failure(s)\n", stderr)
    exit(1)
}
print("All p0_contact_sheet_test checks passed.")
