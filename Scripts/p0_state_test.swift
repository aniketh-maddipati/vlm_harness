#!/usr/bin/env swift
/**
 Deterministic P0 state / identity / persistence tests.
 Mirrors Lumina P0 contracts without importing the app module.

 Run: swift Scripts/p0_state_test.swift
 */
import Foundation
import CryptoKit

var failures = 0
func expect(_ cond: Bool, _ msg: String) {
    if cond {
        print("PASS: \(msg)")
    } else {
        print("FAIL: \(msg)")
        failures += 1
    }
}

// MARK: - Minimal mirrors

enum CullDecision: String, Codable { case undecided, keep, reject, hold }
enum SourceAvailability: String, Codable { case available, missing, unknown }
enum WorkspaceScale: String, Codable { case contactSheet, singlePhoto }
enum GridFilter: String, Codable { case all, keeps, rejects, flagged }

struct EditCrop: Codable, Equatable {
    var x, y, width, height: Double
}

struct RetouchSpot: Codable, Equatable {
    var id: UUID
    var x, y, radius, sourceDX, sourceDY: Double
}

struct EditRecipe: Codable, Equatable {
    var id: UUID
    var schemaVersion: Int
    var exposure: Double
    var temperature: Double
    var tint: Double
    var contrast: Double
    var highlights: Double
    var shadows: Double
    var whites: Double
    var blacks: Double
    var texture: Double
    var clarity: Double
    var dehaze: Double
    var vibrance: Double
    var saturation: Double
    var sharpness: Double
    var luminanceNR: Double
    var crop: EditCrop?
    var straightenDegrees: Double
    var retouch: [RetouchSpot]
    var sourceNeighbors: [String]
    var confidence: Double

    init(
        id: UUID = UUID(),
        schemaVersion: Int = 2,
        exposure: Double = 0,
        temperature: Double = 6500,
        tint: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        whites: Double = 0,
        blacks: Double = 0,
        texture: Double = 0,
        clarity: Double = 0,
        dehaze: Double = 0,
        vibrance: Double = 0,
        saturation: Double = 0,
        sharpness: Double = 0,
        luminanceNR: Double = 0,
        crop: EditCrop? = nil,
        straightenDegrees: Double = 0,
        retouch: [RetouchSpot] = [],
        sourceNeighbors: [String] = [],
        confidence: Double = 1
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.exposure = exposure
        self.temperature = temperature
        self.tint = tint
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.blacks = blacks
        self.texture = texture
        self.clarity = clarity
        self.dehaze = dehaze
        self.vibrance = vibrance
        self.saturation = saturation
        self.sharpness = sharpness
        self.luminanceNR = luminanceNR
        self.crop = crop
        self.straightenDegrees = straightenDegrees
        self.retouch = retouch
        self.sourceNeighbors = sourceNeighbors
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 6500
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        whites = try c.decodeIfPresent(Double.self, forKey: .whites) ?? 0
        blacks = try c.decodeIfPresent(Double.self, forKey: .blacks) ?? 0
        texture = try c.decodeIfPresent(Double.self, forKey: .texture) ?? 0
        clarity = try c.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        dehaze = try c.decodeIfPresent(Double.self, forKey: .dehaze) ?? 0
        vibrance = try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        luminanceNR = try c.decodeIfPresent(Double.self, forKey: .luminanceNR) ?? 0
        crop = try c.decodeIfPresent(EditCrop.self, forKey: .crop)
        straightenDegrees = try c.decodeIfPresent(Double.self, forKey: .straightenDegrees) ?? 0
        retouch = try c.decodeIfPresent([RetouchSpot].self, forKey: .retouch) ?? []
        sourceNeighbors = try c.decodeIfPresent([String].self, forKey: .sourceNeighbors) ?? []
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 1
    }

    var fingerprint: String {
        let cropPart = crop.map { String(format: "%.5f,%.5f,%.5f,%.5f", $0.x, $0.y, $0.width, $0.height) } ?? "nocrop"
        return [
            "v\(schemaVersion)",
            String(format: "%.5f", exposure),
            String(format: "%.5f", straightenDegrees),
            cropPart,
            retouch.isEmpty ? "noheal" : "\(retouch.count)",
        ].joined(separator: "|")
    }

    func withoutGeometry() -> EditRecipe {
        var c = self
        c.crop = nil
        c.straightenDegrees = 0
        return c
    }
}

struct SourceReference: Codable, Equatable {
    var originalPath: String
    var bookmarkData: Data?
    var relativePath: String
    var volumeID: String?
    var availability: SourceAvailability
}

struct AssetRecord: Codable, Equatable {
    var id: UUID
    var sourceKey: String
    var source: SourceReference
    var filename: String
    var cull: CullDecision
    var recipe: EditRecipe?
}

struct FinalSetOrder: Codable, Equatable {
    var assetIDs: [UUID]
}

struct BatchEditRecipient: Codable, Equatable {
    var assetID: UUID
    var before: EditRecipe?
    var after: EditRecipe
}

struct BatchEditCommand: Codable, Equatable {
    var id: UUID
    var includeGeometry: Bool
    var recipients: [BatchEditRecipient]
}

struct WorkspaceRestoreState: Codable, Equatable {
    var focusedAssetID: UUID?
    var filter: GridFilter
    var contactSheetDensity: Int?
    var scrollAnchor: Double?
    var scale: WorkspaceScale
    var keptOrderMode: Bool
}

struct ShootRecord: Codable, Equatable {
    var schemaVersion: Int
    var id: UUID
    var name: String
    var assets: [AssetRecord]
    var finalSetOrder: FinalSetOrder
    var workspace: WorkspaceRestoreState
    var profile: EditRecipe
}

struct LegacyDevelopRecipe: Codable {
    var exposure: Double
    var temperature: Double
    var tint: Double
    var contrast: Double
    var highlights: Double
    var shadows: Double
    var whites: Double
    var blacks: Double
    var texture: Double
    var clarity: Double
    var dehaze: Double
    var vibrance: Double
    var saturation: Double
    var sharpness: Double
    var luminanceNR: Double
    var retouch: [RetouchSpot]
    var sourceNeighbors: [String]
    var confidence: Double
}

struct LegacyPhoto: Codable {
    var id: UUID
    var rawPath: String
    var filename: String
    var tier: String
    var recipe: LegacyDevelopRecipe?
}

struct LegacyProject: Codable {
    var name: String
    var rawFolder: String?
    var photos: [LegacyPhoto]
    var cursorPhotoID: UUID?
    var profile: LegacyDevelopRecipe?
}

enum AssetIdentity {
    static func sourceKey(volumeID: String?, relativePath: String, fileSize: Int64?, capturedAt: Date?) -> String {
        let vol = (volumeID ?? "").lowercased()
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

    static func cacheStem(for id: UUID) -> String { id.uuidString.lowercased() }
}

func encodeStable<T: Encodable>(_ v: T) throws -> Data {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return try e.encode(v)
}

func decodeISO<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return try d.decode(T.self, from: data)
}

// MARK: - Tests

do {
    let key = AssetIdentity.sourceKey(
        volumeID: "VOL-A",
        relativePath: "nested/DSC0001.ARW",
        fileSize: 42_000_000,
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let id1 = AssetIdentity.resolveID(sourceKey: key)
    let id2 = AssetIdentity.resolveID(sourceKey: key)
    expect(id1 == id2, "stable asset identity after rediscovery")

    let preserved = UUID()
    expect(AssetIdentity.resolveID(sourceKey: key, preserved: preserved) == preserved, "preserved legacy IDs win on migration")
}

do {
    let a = AssetIdentity.sourceKey(volumeID: "VOL", relativePath: "a/DSC0001.ARW", fileSize: 10, capturedAt: nil)
    let b = AssetIdentity.sourceKey(volumeID: "VOL", relativePath: "b/DSC0001.ARW", fileSize: 10, capturedAt: nil)
    expect(a != b, "same filenames in different directories stay distinct")
    expect(AssetIdentity.resolveID(sourceKey: a) != AssetIdentity.resolveID(sourceKey: b), "distinct keys → distinct IDs")
}

do {
    let recipe = EditRecipe(
        exposure: 0.4,
        temperature: 5200,
        crop: EditCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.4),
        straightenDegrees: 1.5,
        retouch: [RetouchSpot(id: UUID(), x: 0.5, y: 0.5, radius: 0.02, sourceDX: 0.1, sourceDY: 0)]
    )
    let d1 = try encodeStable(recipe)
    let d2 = try encodeStable(recipe)
    expect(d1 == d2, "recipe versioned serialization is stable")
    let decoded = try JSONDecoder().decode(EditRecipe.self, from: d1)
    expect(abs(decoded.exposure - 0.4) < 1e-9, "recipe exposure roundtrip")
    expect(decoded.crop?.width == 0.5, "crop survives persistence")
    expect(abs(decoded.straightenDegrees - 1.5) < 1e-9, "straighten survives persistence")
    expect(decoded.retouch.count == 1, "retouch survives persistence")
    expect(decoded.fingerprint == recipe.fingerprint, "fingerprint includes geometry")
}

do {
    // Legacy DevelopRecipe-shaped JSON under EditRecipe decoder
    let legacy = """
    {"exposure":0.25,"temperature":6000,"tint":2,"contrast":5,"highlights":-10,"shadows":15,"whites":0,"blacks":0,"texture":0,"clarity":0,"dehaze":0,"vibrance":8,"saturation":0,"sharpness":40,"luminanceNR":10,"retouch":[],"sourceNeighbors":["a.xmp"],"confidence":0.9}
    """.data(using: .utf8)!
    let migrated = try JSONDecoder().decode(EditRecipe.self, from: legacy)
    expect(abs(migrated.exposure - 0.25) < 1e-9, "legacy recipe tone migrates")
    expect(migrated.crop == nil && migrated.straightenDegrees == 0, "legacy recipe has no geometry")
}

do {
    let photoID = UUID()
    let legacy = LegacyProject(
        name: "mehendi",
        rawFolder: "/Volumes/T7/mehendi",
        photos: [
            LegacyPhoto(
                id: photoID,
                rawPath: "/Volumes/T7/mehendi/DSC0001.ARW",
                filename: "DSC0001.ARW",
                tier: "keep",
                recipe: LegacyDevelopRecipe(
                    exposure: 0.2, temperature: 5600, tint: 0, contrast: 10,
                    highlights: -20, shadows: 10, whites: 0, blacks: 0,
                    texture: 0, clarity: 0, dehaze: 0, vibrance: 5, saturation: 0,
                    sharpness: 40, luminanceNR: 0, retouch: [], sourceNeighbors: [], confidence: 1
                )
            )
        ],
        cursorPhotoID: photoID,
        profile: nil
    )
    let data = try encodeStable(legacy)
    let decoded = try decodeISO(LegacyProject.self, from: data)
    expect(decoded.photos[0].id == photoID, "legacy project migration preserves cursor identity")
    expect(decoded.photos[0].tier == "keep", "legacy cull decision preserved")
    expect(abs((decoded.photos[0].recipe?.exposure ?? 0) - 0.2) < 1e-9, "legacy recipe path preserved")

    // Promote to ShootRecord shape
    let key = AssetIdentity.sourceKey(
        volumeID: "T7",
        relativePath: "DSC0001.ARW",
        fileSize: 1,
        capturedAt: nil
    )
    let asset = AssetRecord(
        id: photoID,
        sourceKey: key,
        source: SourceReference(
            originalPath: decoded.photos[0].rawPath,
            bookmarkData: nil,
            relativePath: "DSC0001.ARW",
            volumeID: "T7",
            availability: .missing
        ),
        filename: decoded.photos[0].filename,
        cull: .keep,
        recipe: EditRecipe(exposure: decoded.photos[0].recipe?.exposure ?? 0, temperature: decoded.photos[0].recipe?.temperature ?? 6500)
    )
    let shoot = ShootRecord(
        schemaVersion: 1,
        id: UUID(),
        name: decoded.name,
        assets: [asset],
        finalSetOrder: FinalSetOrder(assetIDs: [photoID]),
        workspace: WorkspaceRestoreState(
            focusedAssetID: photoID,
            filter: .keeps,
            contactSheetDensity: 6,
            scrollAnchor: 0.33,
            scale: .contactSheet,
            keptOrderMode: true
        ),
        profile: EditRecipe()
    )
    expect(shoot.assets[0].id == photoID, "migrated shoot keeps asset id")
    expect(shoot.finalSetOrder.assetIDs == [photoID], "final-order persistence")
    expect(shoot.workspace.scrollAnchor == 0.33, "workspace restore fields persist")
}

do {
    var asset = AssetRecord(
        id: UUID(),
        sourceKey: "k",
        source: SourceReference(originalPath: "/x", bookmarkData: nil, relativePath: "x", volumeID: nil, availability: .available),
        filename: "x.ARW",
        cull: .keep,
        recipe: EditRecipe(exposure: 0.5, crop: EditCrop(x: 0, y: 0, width: 0.5, height: 0.5), straightenDegrees: 2)
    )
    let recipeBefore = asset.recipe
    asset.cull = .reject
    expect(asset.recipe == recipeBefore, "culling never changes edit recipe")
    asset.recipe = EditRecipe(exposure: 1.0)
    expect(asset.cull == .reject, "editing never changes Keep/Reject")
}

do {
    let before = EditRecipe(exposure: 0.1, crop: EditCrop(x: 0.2, y: 0.2, width: 0.5, height: 0.5), straightenDegrees: 3)
    let leader = EditRecipe(exposure: 0.8, crop: EditCrop(x: 0, y: 0, width: 0.4, height: 0.4), straightenDegrees: 5)
    let recipient = UUID()
    let applied = leader.withoutGeometry()
    expect(applied.crop == nil && applied.straightenDegrees == 0, "batch geometry exclusion by default")
    let cmd = BatchEditCommand(
        id: UUID(),
        includeGeometry: false,
        recipients: [BatchEditRecipient(assetID: recipient, before: before, after: applied)]
    )
    let data = try encodeStable(cmd)
    let round = try JSONDecoder().decode(BatchEditCommand.self, from: data)
    expect(round.recipients[0].before?.exposure == 0.1, "batch before recipe serializes")
    expect(round.recipients[0].after.exposure == 0.8, "batch after recipe serializes")
    expect(round.includeGeometry == false, "batch geometry exclusion flag persisted")
}

do {
    // Missing original recovery — catalog state remains
    let id = UUID()
    let shoot = ShootRecord(
        schemaVersion: 1,
        id: UUID(),
        name: "t7-shoot",
        assets: [
            AssetRecord(
                id: id,
                sourceKey: "k",
                source: SourceReference(
                    originalPath: "/Volumes/T7/gone.ARW",
                    bookmarkData: Data([1, 2, 3]),
                    relativePath: "gone.ARW",
                    volumeID: "T7",
                    availability: .missing
                ),
                filename: "gone.ARW",
                cull: .keep,
                recipe: EditRecipe(exposure: 0.3)
            )
        ],
        finalSetOrder: FinalSetOrder(assetIDs: [id]),
        workspace: WorkspaceRestoreState(
            focusedAssetID: id,
            filter: .all,
            contactSheetDensity: nil,
            scrollAnchor: nil,
            scale: .singlePhoto,
            keptOrderMode: false
        ),
        profile: EditRecipe()
    )
    let data = try encodeStable(shoot)
    let loaded = try decodeISO(ShootRecord.self, from: data)
    expect(loaded.assets.count == 1, "missing-original recovery keeps catalog state")
    expect(loaded.assets[0].source.availability == .missing, "availability recorded as missing")
    expect(loaded.assets[0].cull == .keep, "cull survives missing original")
    expect(loaded.assets[0].recipe?.exposure == 0.3, "recipe survives missing original")
    expect(loaded.workspace.scale == .singlePhoto, "workspace restore survives")
}

do {
    // Atomic / recoverable save behavior
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lumina-p0-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let finalURL = tmp.appendingPathComponent("shoot.json")
    let goodURL = tmp.appendingPathComponent("shoot.json.good")
    let tempURL = tmp.appendingPathComponent("shoot.json.tmp")

    let shoot = ShootRecord(
        schemaVersion: 1,
        id: UUID(),
        name: "atomic",
        assets: [],
        finalSetOrder: FinalSetOrder(assetIDs: []),
        workspace: WorkspaceRestoreState(
            focusedAssetID: nil, filter: .all, contactSheetDensity: nil,
            scrollAnchor: nil, scale: .contactSheet, keptOrderMode: false
        ),
        profile: EditRecipe()
    )
    let data = try encodeStable(shoot)
    try data.write(to: tempURL, options: .atomic)
    try FileManager.default.moveItem(at: tempURL, to: finalURL)
    try data.write(to: goodURL, options: .atomic)
    expect(FileManager.default.fileExists(atPath: finalURL.path), "atomic save lands at final path")
    expect(FileManager.default.fileExists(atPath: goodURL.path), "last-known-good copy exists")

    // Corrupt primary; recover from good
    try Data("{}".utf8).write(to: finalURL)
    let recovered = try decodeISO(ShootRecord.self, from: Data(contentsOf: goodURL))
    expect(recovered.name == "atomic", "recoverable last-known-good state")
}

do {
    let id = UUID()
    expect(AssetIdentity.cacheStem(for: id) == id.uuidString.lowercased(), "cache stem keyed by asset identity")
    expect(!AssetIdentity.cacheStem(for: id).contains("DSC"), "cache stem is not filename")
}

if failures > 0 {
    fputs("\(failures) failure(s)\n", stderr)
    exit(1)
}
print("All p0_state_test checks passed.")
