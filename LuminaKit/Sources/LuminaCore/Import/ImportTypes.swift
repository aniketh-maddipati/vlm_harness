import Foundation
import CoreGraphics
import ImageIO

// WP-2. Import: what a file is, whether it decodes, what the result message says (R-10…R-16).

public enum ImportKind: Equatable, Sendable { case photo, raw, video, archive, sidecar, system, empty, other }

/// Why a file was skipped, as counted in the result message (R-12).
public enum SkipReason: Hashable, Sendable, CaseIterable { case video, archive, damaged, empty, other, heic, duplicate }

public struct ImageInfo: Equatable, Sendable {
    /// Pixel size after EXIF orientation is applied (R-1D).
    public var pixelSize: CGSize
    public init(pixelSize: CGSize) { self.pixelSize = pixelSize }
}

public struct EXIF: Equatable, Sendable {
    public var shot: Date?
    public var make: String?, model: String?, lens: String?
    public var fNumber: Double?, exposure: Double?, focal: Double?
    public var iso: Int?
    public var orientation: Int = 1
    public init() {}
}

/// One file on its way into a shoot.
public struct ImportItem: Equatable, Sendable {
    /// Path from the imported folder down, the folder's own name first ("Trip/Day 1/a.jpg"); a
    /// loose file is just its name. The last folder in it is the scene's title.
    public var rel: String
    public var url: URL?
    public var shot: Date?
    public var aspect: Double
    public var size: Int64
    public var modified: Date?
    public var exif: EXIF?
    public init(rel: String, url: URL? = nil, shot: Date? = nil, aspect: Double = 1.5, size: Int64 = 0, modified: Date? = nil, exif: EXIF? = nil) {
        self.rel = rel; self.url = url; self.shot = shot; self.aspect = aspect; self.size = size; self.modified = modified; self.exif = exif
    }
    /// Same relative path, size and modified time = the same photo (R-14).
    public var dedupeKey: String { "\(rel)|\(size)|\(modified.map { Int($0.timeIntervalSince1970) } ?? 0)" }
}

public enum ImportClassifier {
    static let system: Set<String> = [".ds_store", "thumbs.db", "desktop.ini"]
    static let sidecars: Set<String> = ["xmp", "thm", "lrv", "aae", "dop", "pp3", "on1", "cos", "lrcat"]
    static let raws: Set<String> = ["arw", "cr2", "cr3", "nef", "nrw", "dng", "raf", "orf", "rw2", "pef", "srw", "x3f", "3fr", "iiq", "erf", "raw"]
    static let videos: Set<String> = ["mp4", "mov", "m4v", "avi", "mts", "m2ts", "mkv", "webm", "mxf"]
    static let archives: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "dmg"]
    static let photos: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "avif", "tif", "tiff", "gif", "bmp"]

    /// By name and size only. The extension is a hint: `.photo` and `.raw` still have to decode.
    public static func classify(name: String, size: Int64) -> ImportKind {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // An extension is one to five letters or digits; anything else ("holiday.final version") is
        // no extension at all, and the file is tried as a photo.
        let tail = lower.split(separator: ".", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let ext = lower.contains(".") && (1...5).contains(tail.count) && tail.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) ? tail : ""
        if system.contains(lower) || lower.hasPrefix(".") || lower == "icon\r" { return .system }
        if sidecars.contains(ext) { return .sidecar }
        if size == 0 { return .empty }
        if raws.contains(ext) { return .raw }
        if videos.contains(ext) { return .video }
        if archives.contains(ext) { return .archive }
        if photos.contains(ext) || ext.isEmpty { return .photo }
        return .other
    }

    /// Nil when the file won't decode as an image, whatever its name says (R-10). RAW goes
    /// through ImageIO like everything else: bytes that only carry a RAW extension are nil.
    public static func decodes(url: URL) -> ImageInfo? { ImageProbe.probe(url)?.info }
}

public struct ImportSummary: Equatable, Sendable {
    public var added: Int
    public var folder: String?
    public var skipped: [SkipReason: Int]
    /// The folder had no files at all.
    public var emptyFolder = false
    public init(added: Int, folder: String? = nil, skipped: [SkipReason: Int] = [:], emptyFolder: Bool = false) {
        self.added = added; self.folder = folder; self.skipped = skipped; self.emptyFolder = emptyFolder
    }
    /// Reading the files failed (a folder that went away mid-import).
    public static let wentWrong = "Something went wrong reading those files. Nothing was changed."
    public static let opens = "Lumina opens JPEG, PNG, WebP, HEIC, AVIF and RAW."

    public var message: String {
        if emptyFolder { return "That folder is empty." }
        let order: [(SkipReason, (Int) -> String)] = [
            (.video, { "\($0) video\($0 == 1 ? "" : "s")" }), (.archive, { "\($0) zip/archive (unzip it first)" }),
            (.damaged, { "\($0) damaged or not really a photo" }), (.empty, { "\($0) empty (0 bytes)" }),
            (.other, { "\($0) not a photo" }), (.heic, { "\($0) HEIC this Mac can’t open" }),
            (.duplicate, { "\($0) already in this shoot" })]
        let parts = order.compactMap { r, f in skipped[r].flatMap { $0 > 0 ? f($0) : nil } }
        let skip = parts.isEmpty ? "" : " Skipped " + parts.joined(separator: " · ") + "."
        if added == 0 { return (parts.isEmpty ? "No photos found there." : "No photos added." + skip) + " " + Self.opens }
        return "Added \(added) photo\(added == 1 ? "" : "s")" + (folder.map { " from \($0)" } ?? "") + "." + skip
    }
}
