import Foundation
import CoreGraphics

// WP-0 contract: the seams to the backend. LuminaKit ships plain defaults (ImageIO, JSON files,
// a recording exporter) so the UI runs and tests without the app; the app target swaps in adapters
// over Lumina/Sets/Core and Lumina/Sets/Look (`Lumina/Native/Backend`).

/// Decodes pictures. Never called on the main thread's time: every call is async.
public protocol ImageProvider: AnyObject, Sendable {
    /// The photo at `maxPixel` on its longest side (already orientation-corrected), with `look`
    /// applied when given. Throws when the file can't be opened (R-44).
    func image(for photo: Photo, maxPixel: Int, look: Look?) async throws -> CGImage
    /// A hint: decode these soon, at low priority (R-42).
    func preload(_ photos: [Photo], maxPixel: Int)
    /// Drop what was preloaded for photos no longer near the current one.
    func cancelPreloads()
}

/// What Save writes (README §4). Runs off the main thread (R-83).
public struct ExportJob: Sendable {
    public struct Item: Sendable {
        public var photo: Photo
        /// Nil = as shot.
        public var look: Look?
        public init(photo: Photo, look: Look?) { self.photo = photo; self.look = look }
    }
    public var format: SaveFormat
    public var items: [Item]
    /// Where Folder and JPEG copies go. XMP sidecars go next to each RAW.
    public var destination: URL?
    /// Only these ids changed since the last save ("Only what changed is rewritten").
    public var changedOnly: Set<String>?
    public init(format: SaveFormat, items: [Item], destination: URL?, changedOnly: Set<String>? = nil) {
        self.format = format; self.items = items; self.destination = destination; self.changedOnly = changedOnly
    }
}

public struct ExportResult: Sendable {
    public var written: Int
    public var failed: [String: String]
    /// What "Show in Finder" reveals.
    public var reveal: URL?
    public init(written: Int, failed: [String: String] = [:], reveal: URL? = nil) { self.written = written; self.failed = failed; self.reveal = reveal }
}

public protocol Exporter: AnyObject, Sendable {
    func export(_ job: ExportJob) async -> ExportResult
}

/// Everything that must survive a relaunch (R-70). One snapshot per shoot key plus the flow.
public struct Snapshot: Codable, Sendable, Equatable {
    public var shootKey: String
    public var step: Step
    public var cur: String?
    public var copied: Int
    public var keep: [String: Bool]
    public var looks: [String: Look]
    public var tags: [String: String]
    public var done: [String]
    public var fmt: SaveFormat
    public var withEdits: Bool
    public var saved: SavedRecord?
    public var destination: String?
    /// Imported folder to offer (or reopen through its bookmark) after a relaunch (R-19).
    public var folderName: String?
    public var folderBookmark: Data?
    public var folderPath: String?
    public var photoCount: Int
    /// Bumped on every write; another window seeing a newer one shows "Changed in another window".
    public var revision: Int
    public var writer: String
    public init(shootKey: String, step: Step = .open, cur: String? = nil, copied: Int = 0, keep: [String: Bool] = [:],
                looks: [String: Look] = [:], tags: [String: String] = [:], done: [String] = [], fmt: SaveFormat = .xmp,
                withEdits: Bool = true, saved: SavedRecord? = nil, destination: String? = nil, folderName: String? = nil,
                folderBookmark: Data? = nil, folderPath: String? = nil, photoCount: Int = 0, revision: Int = 0, writer: String = "") {
        self.shootKey = shootKey; self.step = step; self.cur = cur; self.copied = copied; self.keep = keep
        self.looks = looks; self.tags = tags; self.done = done; self.fmt = fmt; self.withEdits = withEdits
        self.saved = saved; self.destination = destination; self.folderName = folderName
        self.folderBookmark = folderBookmark; self.folderPath = folderPath; self.photoCount = photoCount
        self.revision = revision; self.writer = writer
    }
}

public enum PersistenceError: Error { case storageFull, unreadable(String) }

public protocol PersistenceStore: AnyObject, Sendable {
    /// The last snapshot written, whichever shoot it was for.
    func loadLast() throws -> Snapshot?
    func load(shootKey: String) throws -> Snapshot?
    /// Throws `PersistenceError.storageFull` when the disk is full (R-71).
    func save(_ snapshot: Snapshot) throws
    func clear(shootKey: String) throws
    /// Called (on any queue) when another window or process wrote `shootKey` (R-72).
    func observe(_ onChange: @escaping @Sendable (Snapshot) -> Void)
}

/// A card or folder that can be opened into a `Shoot`.
public protocol ShootSource: Sendable {
    func load() async throws -> Shoot
}

/// The services a window runs on. Tests and the snapshot tool pass their own.
public struct Services: Sendable {
    public var images: any ImageProvider
    public var exporter: any Exporter
    public var persistence: any PersistenceStore
    public init(images: any ImageProvider, exporter: any Exporter, persistence: any PersistenceStore) {
        self.images = images; self.exporter = exporter; self.persistence = persistence
    }
}
