import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Photo/media types Lumina can import — RAW, JPEG, HEIC, and anything ImageIO can open.
enum MediaFormats {
    static let knownExtensions: Set<String> = [
        // RAW
        "ARW", "CR2", "CR3", "NEF", "NRW", "DNG", "ORF", "RW2", "RAF", "PEF",
        "SRW", "IIQ", "3FR", "FFF", "MOS", "MRW", "X3F", "RAW",
        // Processed / camera JPEG
        "JPG", "JPEG", "JPE", "HEIC", "HEIF", "HIF",
        // Other bitmaps
        "PNG", "TIF", "TIFF", "WEBP", "BMP", "GIF", "AVIF", "JP2", "JXL",
    ]

    static var utTypes: [UTType] {
        [.image, .jpeg, .heic, .png, .tiff, .gif, .webP, .rawImage]
    }

    static func isImportable(_ url: URL) -> Bool {
        let ext = url.pathExtension.uppercased()
        if knownExtensions.contains(ext) { return true }
        // Unusual / missing extension — accept if ImageIO can read it
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return false }
        return true
    }

    /// Collect importable photos from folders and/or explicit file picks.
    static func collectPhotos(from urls: [URL]) -> [URL] {
        var files: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let kids = try? fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    files.append(contentsOf: kids.filter(isImportable))
                }
            } else if isImportable(url) {
                files.append(url)
            }
        }
        return files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static var exiftoolExtensions: [String] {
        Array(knownExtensions).sorted()
    }
}
