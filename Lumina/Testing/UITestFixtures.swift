#if DEBUG
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deterministic, repository-safe fixture shoots for the XCUITest harness.
///
/// Fixtures are generated at launch into the isolated UI-test state directory — never committed,
/// never touching the maintainer's real catalog. Images are small synthesized JPEGs (no Sony RAW,
/// no large binaries). State (cull decisions, edited marks, preview cache) is seeded so the app
/// opens into a rich, scroll-worthy sheet; every subsequent action still runs through the real
/// P0 command + persistence paths.
///
/// Determinism: everything is a pure function of the asset index. No RNG, no wall-clock — capture
/// dates are derived from a fixed epoch so chronological ordering is stable across machines.
enum UITestFixtures {
    struct Spec {
        let name: String
        let count: Int
        /// When true, a deterministic subset of originals is removed after caching previews,
        /// leaving cached previews present but originals unavailable.
        let dropOriginals: Bool
    }

    static let specs: [String: Spec] = [
        "mixed-60": Spec(name: "mixed-60", count: 60, dropOriginals: false),
        "mixed-200": Spec(name: "mixed-200", count: 200, dropOriginals: false),
        "missing-originals": Spec(name: "missing-originals", count: 48, dropOriginals: true),
    ]

    /// Fixed epoch so seeded capture dates never depend on the wall clock.
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Build (or reuse) the requested fixture inside the current UI-test state directory.
    /// Returns the shoot name that the harness should open, or nil when the fixture is unknown.
    @discardableResult
    static func ensure(named fixture: String, reset: Bool) -> String? {
        guard let spec = specs[fixture] else {
            fputs("[UITestFixtures] unknown fixture \(fixture)\n", stderr)
            return nil
        }

        // Relaunch against the same state must preserve prior decisions: only rebuild on reset
        // or when the shoot is absent.
        if !reset, let existing = try? ShootStore.loadShoot(id: spec.name), !existing.assets.isEmpty {
            return existing.name
        }

        do {
            try build(spec)
            return spec.name
        } catch {
            fputs("[UITestFixtures] build failed for \(spec.name): \(error)\n", stderr)
            return nil
        }
    }

    // MARK: - Build

    private static func build(_ spec: Spec) throws {
        let support = try ShootStore.supportDirectory()
        let imagesDir = support
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent(spec.name, isDirectory: true)
        // Clean rebuild of the image folder.
        try? FileManager.default.removeItem(at: imagesDir)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let gridDir = try ShootStore.cacheDirectory(for: spec.name, tier: "grid512")
        let previewDir = try ShootStore.cacheDirectory(for: spec.name, tier: "preview")

        var assets: [AssetRecord] = []
        assets.reserveCapacity(spec.count)

        for index in 0..<spec.count {
            let shape = shape(for: index)
            let filename = String(format: "IMG_%04d.jpg", index)
            let originalURL = imagesDir.appendingPathComponent(filename)
            guard let jpeg = renderJPEG(index: index, width: shape.width, height: shape.height) else {
                continue
            }
            try jpeg.write(to: originalURL)

            let source = SourceReference.make(fileURL: originalURL, rootURL: imagesDir)
            let sourceKey = AssetIdentity.sourceKey(
                volumeID: source.volumeID,
                relativePath: source.relativePath,
                fileSize: Int64(jpeg.count),
                capturedAt: nil
            )
            let assetID = AssetIdentity.resolveID(sourceKey: sourceKey)

            // Seed identity-keyed preview cache (grid + preview) directly from the same bytes.
            let previewURL = previewDir.appendingPathComponent(AssetIdentity.cacheStem(for: assetID) + ".jpg")
            let gridURL = gridDir.appendingPathComponent(AssetIdentity.cacheStem(for: assetID) + ".jpg")
            try jpeg.write(to: previewURL)
            try jpeg.write(to: gridURL)

            let state = state(for: index)
            var missing = false
            if spec.dropOriginals, index % 3 == 0 {
                // Original intentionally unavailable; cached previews remain.
                try? FileManager.default.removeItem(at: originalURL)
                missing = true
            }

            var asset = AssetRecord(
                id: assetID,
                sourceKey: sourceKey,
                source: source,
                filename: filename,
                cull: state.cull,
                recipe: state.edited ? editedRecipe(index: index) : nil,
                capturedAt: epoch.addingTimeInterval(Double(index) * 3.0),
                fileSize: Int64(jpeg.count),
                thumbPath: previewURL.path,
                gridThumbPath: gridURL.path,
                previewOrigin: .embedded,
                previewLongEdge: max(shape.width, shape.height),
                isFlagged: state.flagged
            )
            asset.source.availability = missing ? .missing : .available
            if missing {
                asset.source.lastSeenAt = epoch
            }
            asset.userDecidedAt = state.cull == .undecided ? nil : epoch.addingTimeInterval(Double(index))
            assets.append(asset)
        }

        var rawRef = SourceReference(
            originalPath: imagesDir.path,
            relativePath: "",
            volumeID: AssetIdentity.volumeIdentifier(for: imagesDir),
            availability: .available,
            lastSeenAt: epoch
        )
        rawRef.bookmarkData = nil // Unsandboxed dev build resolves by path; no bookmark needed.

        var shoot = ShootRecord(
            id: deterministicUUID("shoot:\(spec.name)"),
            name: spec.name,
            createdAt: epoch,
            rawFolder: rawRef,
            assets: assets
        )
        // Start on the contact sheet with a stable focus so restore is deterministic.
        shoot.workspace = WorkspaceRestoreState(
            focusedAssetID: assets.first?.id,
            filter: .all,
            contactSheetDensity: 6,
            scrollAnchor: 0,
            scale: .contactSheet,
            keptOrderMode: false
        )
        try ShootStore.saveShoot(shoot)
    }

    // MARK: - Deterministic state assignment

    private struct SeededState {
        var cull: CullDecision
        var edited: Bool
        var flagged: Bool
    }

    /// Pure function of index → presentation state. Produces a mixture of unreviewed / kept /
    /// rejected / edited (and a few flagged) with repeated runs so grouping-like frames appear.
    private static func state(for index: Int) -> SeededState {
        let cull: CullDecision
        switch index % 7 {
        case 0, 1: cull = .keep
        case 2: cull = .reject
        case 3: cull = .hold
        default: cull = .undecided
        }
        let edited = index % 5 == 0            // edited marks overlap keep/reject deliberately
        let flagged = index % 11 == 0
        return SeededState(cull: cull, edited: edited, flagged: flagged)
    }

    private struct Shape { let width: Int; let height: Int }

    /// Alternating portrait / landscape with a few square frames, plus repeated-looking runs.
    private static func shape(for index: Int) -> Shape {
        switch index % 6 {
        case 0, 3: return Shape(width: 240, height: 160)   // landscape 3:2
        case 1, 4: return Shape(width: 160, height: 240)   // portrait 2:3
        case 2: return Shape(width: 200, height: 200)      // square
        default: return Shape(width: 240, height: 160)     // repeated landscape
        }
    }

    private static func editedRecipe(index: Int) -> EditRecipe {
        // Any non-nil recipe drives the "edited" mark; keep it minimal and deterministic.
        EditRecipe.neutral.forked(id: deterministicUUID("recipe:\(index)"))
    }

    // MARK: - Image synthesis

    private static func renderJPEG(index: Int, width: Int, height: Int) -> Data? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        // Deterministic hue; alternating bright / dark base so the sheet has tonal variety.
        let bright = index % 2 == 0
        let hue = CGFloat((index * 47) % 360) / 360.0
        let brightness: CGFloat = bright ? 0.78 : 0.24
        let base = NSColor(calibratedHue: hue, saturation: 0.45, brightness: brightness, alpha: 1)
        ctx.setFillColor(base.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // A contrasting corner band gives each frame a stable, orientation-revealing landmark.
        let band = NSColor(calibratedHue: hue, saturation: 0.55, brightness: bright ? 0.35 : 0.85, alpha: 1)
        ctx.setFillColor(band.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: max(6, height / 8)))

        guard let image = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: - Deterministic UUIDs (stable IDs across runs and machines)

    private static func deterministicUUID(_ seed: String) -> UUID {
        var hasher = FNV1aUUIDMixer()
        hasher.update(seed)
        return hasher.uuid()
    }
}

/// Minimal FNV-1a-based 128-bit mixer for stable UUIDs without importing CryptoKit here.
/// Not cryptographic — used only for fixture-owned record IDs (shoot id, edit-recipe id).
/// Asset IDs still come from `AssetIdentity`'s real SHA-256 derivation.
private struct FNV1aUUIDMixer {
    private var h1: UInt64 = 0xcbf29ce484222325
    private var h2: UInt64 = 0x84222325cbf29ce4

    mutating func update(_ string: String) {
        for byte in string.utf8 {
            h1 = (h1 ^ UInt64(byte)) &* 0x100000001b3
            h2 = (h2 &* 0x100000001b3) ^ UInt64(byte)
        }
    }

    func uuid() -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: h1.bigEndian) { for i in 0..<8 { bytes[i] = $0[i] } }
        withUnsafeBytes(of: h2.bigEndian) { for i in 0..<8 { bytes[8 + i] = $0[i] } }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
#endif
