import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum ProjectStore {
    static func supportDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumina", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func projectDirectory(for name: String) throws -> URL {
        let dir = try supportDirectory().appendingPathComponent("projects/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cacheDirectory(for projectName: String, tier: String) throws -> URL {
        let dir = try projectDirectory(for: projectName)
            .appendingPathComponent("cache/\(tier)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var persistWorkItem: DispatchWorkItem?

    static func projectJSONURL(for name: String) throws -> URL {
        try projectDirectory(for: name).appendingPathComponent("project.json")
    }

    static func load(name: String) throws -> LuminaProject {
        let url = try projectJSONURL(for: name)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LuminaProject.self, from: data)
    }

    static func loadLastProject() throws -> LuminaProject? {
        guard let name = lastProjectName() else { return nil }
        return try load(name: name)
    }

    static func lastProjectName() -> String? {
        let url = try? supportDirectory().appendingPathComponent("last_project.txt")
        guard let url,
              let name = try? String(contentsOf: url, encoding: .utf8),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func saveLastProjectName(_ name: String) {
        guard let url = try? supportDirectory().appendingPathComponent("last_project.txt") else { return }
        try? name.write(to: url, atomically: true, encoding: .utf8)
    }

    static func save(_ project: LuminaProject) throws {
        let url = try projectDirectory(for: project.name).appendingPathComponent("project.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(project).write(to: url, options: .atomic)
        saveLastProjectName(project.name)
    }

    /// Debounced persist — coalesces rapid tier/keyboard changes.
    @MainActor
    static func saveDebounced(_ project: LuminaProject, delay: TimeInterval = 0.5) {
        persistWorkItem?.cancel()
        let snapshot = project
        let work = DispatchWorkItem {
            try? save(snapshot)
        }
        persistWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: work)
    }
}

enum PreviewExtractor {
    private static let processedExtensions: Set<String> = [
        "JPG", "JPEG", "JPE", "HEIC", "HEIF", "HIF", "PNG", "TIF", "TIFF", "WEBP",
    ]

    /// Best available pixels — full decode for JPG/HEIC, embedded preview for RAW.
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
        // Already a JPEG and ImageIO failed oddly — copy/downscale as last resort for bitmaps
        let ext = rawURL.pathExtension.uppercased()
        if ["JPG", "JPEG", "JPE"].contains(ext),
           downscaleJPEG(from: rawURL, to: destURL, maxPixelSize: maxPixelSize) {
            return
        }
        // RAW fallback: embedded preview via exiftool
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

    /// Decode full image (not embedded thumbnail) for JPG/HEIC/PNG from iCloud, phone exports, etc.
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

    /// Full demosaic path via ImageIO (macOS RAW decoder — LibRaw-quality substitute for Sony ARW).
    static func demosaicFull(from rawURL: URL, maxPixelSize: Int = 6000) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(rawURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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
