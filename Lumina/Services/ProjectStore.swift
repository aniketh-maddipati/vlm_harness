import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Compatibility facade over `ShootStore`. Prefer ShootStore for new P0 code.
enum ProjectStore {
    static func supportDirectory() throws -> URL {
        try ShootStore.supportDirectory()
    }

    static func projectDirectory(for name: String) throws -> URL {
        try ShootStore.shootDirectory(for: name)
    }

    static func cacheDirectory(for projectName: String, tier: String) throws -> URL {
        try ShootStore.cacheDirectory(for: projectName, tier: tier)
    }

    /// Cache file keyed by stable asset identity (not filename stem).
    static func cacheFileURL(projectName: String, tier: String, assetID: UUID) throws -> URL {
        try ShootStore.cacheFileURL(shootName: projectName, tier: tier, assetID: assetID)
    }

    static func projectJSONURL(for name: String) throws -> URL {
        try ShootStore.shootJSONURL(for: name)
    }

    static func load(name: String) throws -> LuminaProject {
        let shoot = try ShootStore.loadShoot(id: name)
        return ShootMigration.project(from: shoot)
    }

    static func loadLastProject() throws -> LuminaProject? {
        guard let name = lastProjectName() else { return nil }
        return try load(name: name)
    }

    static func lastProjectName() -> String? {
        ShootStore.lastOpenedShootName()
    }

    static func saveLastProjectName(_ name: String) {
        guard let url = try? supportDirectory().appendingPathComponent("last_project.txt") else { return }
        do {
            try name.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Lumina: failed to write last_project.txt: \(error.localizedDescription)")
        }
    }

    static func save(_ project: LuminaProject) throws {
        var shoot = ShootMigration.shoot(from: project)
        if let existing = try? ShootStore.loadShoot(id: project.name) {
            shoot.id = project.shootID ?? existing.id
        }
        try ShootStore.saveShoot(shoot)
    }

    /// Debounced persist — per-shoot, not one global work item.
    @MainActor
    static func saveDebounced(_ project: LuminaProject, delay: TimeInterval = 0.5) {
        let shoot = ShootMigration.shoot(from: project)
        let nanos = UInt64(max(delay, 0) * 1_000_000_000)
        Task {
            await ShootStore.shared.saveShootDebounced(shoot, delayNanoseconds: nanos)
        }
    }

    static func lastPersistenceError(for name: String) async -> String? {
        await ShootStore.shared.lastPersistenceError(for: name)
    }
}

nonisolated enum PreviewExtractor {
    private static let processedExtensions: Set<String> = [
        "JPG", "JPEG", "JPE", "HEIC", "HEIF", "HIF", "PNG", "TIF", "TIFF", "WEBP",
    ]

    /// Fastest path — embedded/thumbnail JPEG only; no full demosaic or exiftool unless ImageIO fails.
    @discardableResult
    static func extractEmbeddedFast(to destURL: URL, from sourceURL: URL, maxPixelSize: Int = 1024) -> Bool {
        if FileManager.default.fileExists(atPath: destURL.path) { return true }
        let result = extractBrowsePreview(to: destURL, from: sourceURL, maxPixelSize: maxPixelSize)
        return result.success
    }

    /// Narrative-style browse currency: camera embedded JPEG preferred; synthesize once if too small.
    /// - Important: interactive path never demosaics again — this runs only at ingest.
    static func extractBrowsePreview(
        to destURL: URL,
        from sourceURL: URL,
        maxPixelSize: Int = 2400,
        minLongEdge: Int = 2000
    ) -> (success: Bool, origin: PreviewOrigin, longEdge: Int) {
        if FileManager.default.fileExists(atPath: destURL.path) {
            let edge = jpegLongEdge(at: destURL)
            return (true, .unknown, edge)
        }

        let ext = sourceURL.pathExtension.uppercased()
        if processedExtensions.contains(ext) {
            if extractFullImage(to: destURL, from: sourceURL, maxPixelSize: maxPixelSize) {
                return (true, .processed, jpegLongEdge(at: destURL))
            }
            return (false, .unknown, 0)
        }

        if let embedded = readEmbeddedThumbnail(from: sourceURL, maxPixelSize: maxPixelSize) {
            let edge = max(embedded.width, embedded.height)
            if edge >= minLongEdge, writeJPEG(cgImage: embedded, to: destURL, quality: 0.92) {
                return (true, .embedded, edge)
            }
        }

        if let synth = synthesizeBrowsePreview(from: sourceURL, maxPixelSize: maxPixelSize),
           writeJPEG(cgImage: synth, to: destURL, quality: 0.9) {
            return (true, .synthesized, max(synth.width, synth.height))
        }

        if extractWithImageIO(to: destURL, from: sourceURL, maxPixelSize: maxPixelSize) {
            return (true, .synthesized, jpegLongEdge(at: destURL))
        }
        return (false, .unknown, 0)
    }

    private static func readEmbeddedThumbnail(from url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func synthesizeBrowsePreview(from url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func jpegLongEdge(at url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return 0
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        return max(w, h)
    }

    static func extractBest(to destURL: URL, from sourceURL: URL, maxPixelSize: Int) throws {
        let ext = sourceURL.pathExtension.uppercased()
        if processedExtensions.contains(ext) {
            if extractFullImage(to: destURL, from: sourceURL, maxPixelSize: maxPixelSize) {
                return
            }
        }
        try extract(to: destURL, from: sourceURL, maxPixelSize: maxPixelSize)
    }

    static func extract(to destURL: URL, from rawURL: URL, maxPixelSize: Int) throws {
        if extractWithImageIO(to: destURL, from: rawURL, maxPixelSize: maxPixelSize) {
            return
        }
        let ext = rawURL.pathExtension.uppercased()
        if ["JPG", "JPEG", "JPE"].contains(ext),
           downscaleJPEG(from: rawURL, to: destURL, maxPixelSize: maxPixelSize) {
            return
        }
        guard ExifToolService.isAvailable else {
            throw ExifToolError.previewExtractionFailed(rawURL.lastPathComponent)
        }
        let temp = destURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".jpg")
        try ExifToolService.extractPreview(from: rawURL, to: temp)
        if maxPixelSize < 3000 {
            _ = downscaleJPEG(from: temp, to: destURL, maxPixelSize: maxPixelSize)
            try? FileManager.default.removeItem(at: temp)
        } else {
            try? FileManager.default.moveItem(at: temp, to: destURL)
        }
    }

    @discardableResult
    static func extractWithImageIO(to destURL: URL, from rawURL: URL, maxPixelSize: Int) -> Bool {
        guard let source = CGImageSourceCreateWithURL(rawURL as CFURL, nil) else { return false }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return false
        }
        return writeJPEG(cgImage: image, to: destURL, quality: 0.92)
    }

    @discardableResult
    static func extractFullImage(to destURL: URL, from url: URL, maxPixelSize: Int) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        guard let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        let maxDim = max(full.width, full.height)
        if maxDim <= maxPixelSize {
            return writeJPEG(cgImage: full, to: destURL, quality: 0.94)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return writeJPEG(cgImage: full, to: destURL, quality: 0.92)
        }
        return writeJPEG(cgImage: scaled, to: destURL, quality: 0.94)
    }

    static func renderedFallback(from rawURL: URL, maxPixelSize: Int = 6000) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(rawURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    @available(*, deprecated, renamed: "renderedFallback(from:maxPixelSize:)")
    static func demosaicFull(from rawURL: URL, maxPixelSize: Int = 6000) -> CGImage? {
        renderedFallback(from: rawURL, maxPixelSize: maxPixelSize)
    }

    static func downscaleJPEG(from src: URL, to dest: URL, maxPixelSize: Int) -> Bool {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil) else { return false }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return false
        }
        return writeJPEG(cgImage: image, to: dest, quality: 0.92)
    }

    static func writeJPEG(cgImage: CGImage, to url: URL, quality: CGFloat) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        let opts = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(dest, cgImage, opts)
        return CGImageDestinationFinalize(dest)
    }
}
