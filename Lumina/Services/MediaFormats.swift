import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PhotoDiscoveryResult: Sendable {
    var importable: [URL]
    var skipped: [IngestSkippedFile]
    var discoveredCount: Int
}

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

    static let videoExtensions: Set<String> = [
        "MP4", "MOV", "M4V", "AVI", "MKV", "MTS", "M2TS", "LRF",
    ]

    static let sidecarExtensions: Set<String> = [
        "XMP", "LRPREV", "LRDATA",
    ]

    private static let skipDirectoryNames: Set<String> = [
        ".trashes", ".fseventsd", ".spotlight-v100", ".documentrevisions-v100",
        "__macosx", ".photoslibrary", "node_modules", ".git",
    ]

    static var utTypes: [UTType] {
        [.image, .jpeg, .heic, .png, .tiff, .gif, .webP, .rawImage]
    }

    static func isImportable(_ url: URL) -> Bool {
        let ext = url.pathExtension.uppercased()
        if videoExtensions.contains(ext) { return false }
        if ext == "XMP" || ext == "LRPREV" { return false }
        if knownExtensions.contains(ext) { return true }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return false }
        return true
    }

    static func isSidecar(_ url: URL) -> Bool {
        let ext = url.pathExtension.uppercased()
        return ext == "XMP" || ext == "LRPREV" || ext == "LRDATA"
    }

    /// Shallow collect — kept for compatibility; prefers deep discovery.
    static func collectPhotos(from urls: [URL]) -> [URL] {
        var merged: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                merged.append(contentsOf: discoverPhotos(at: url).importable)
            } else if isImportable(url) {
                merged.append(url)
            }
        }
        return merged.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// Recursive discovery with dedup and skip accounting.
    static func discoverPhotos(at root: URL, maxDepth: Int = 10) -> PhotoDiscoveryResult {
        var importable: [URL] = []
        var skipped: [IngestSkippedFile] = []
        var seenKeys = Set<String>()
        var discoveredCount = 0

        func dedupKey(for url: URL) -> String? {
            guard let values = try? url.resourceValues(forKeys: [
                .fileResourceIdentifierKey, .fileSizeKey,
            ]),
                  let id = values.fileResourceIdentifier as? NSObject else {
                return "\(url.path)|\((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)"
            }
            let size = values.fileSize ?? 0
            return "\(id.hash)|\(size)"
        }

        func walk(_ dir: URL, depth: Int) {
            guard depth <= maxDepth else { return }
            let name = dir.lastPathComponent.lowercased()
            if skipDirectoryNames.contains(name) || name.hasPrefix(".") && name != "." {
                return
            }

            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for entry in entries {
                let entryName = entry.lastPathComponent.lowercased()
                if entryName.hasPrefix(".") { continue }

                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir) else { continue }

                if isDir.boolValue {
                    if skipDirectoryNames.contains(entryName) { continue }
                    walk(entry, depth: depth + 1)
                    continue
                }

                discoveredCount += 1
                let ext = entry.pathExtension.uppercased()

                if videoExtensions.contains(ext) {
                    skipped.append(IngestSkippedFile(path: entry.path, reason: .video))
                    continue
                }
                if isSidecar(entry) {
                    skipped.append(IngestSkippedFile(path: entry.path, reason: .sidecar))
                    continue
                }
                guard isImportable(entry) else {
                    skipped.append(IngestSkippedFile(path: entry.path, reason: .unsupported))
                    continue
                }
                guard let key = dedupKey(for: entry) else { continue }
                if seenKeys.contains(key) {
                    skipped.append(IngestSkippedFile(path: entry.path, reason: .duplicate))
                    continue
                }
                seenKeys.insert(key)
                importable.append(entry)
            }
        }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue {
            walk(root, depth: 0)
        } else if isImportable(root) {
            discoveredCount = 1
            importable = [root]
        }

        importable.sort {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        return PhotoDiscoveryResult(
            importable: importable,
            skipped: skipped,
            discoveredCount: max(discoveredCount, importable.count + skipped.count)
        )
    }

    static func countImportable(in folder: URL) -> Int {
        discoverPhotos(at: folder, maxDepth: 3).importable.count
    }

    static var exiftoolExtensions: [String] {
        Array(knownExtensions).sorted()
    }
}
