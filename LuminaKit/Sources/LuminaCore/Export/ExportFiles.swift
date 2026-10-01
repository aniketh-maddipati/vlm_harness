import CryptoKit
import Foundation

// WP-7. Every byte Save writes lands through here. The trust rules (AGENTS.md):
// - a file being replaced is first kept as `<name>.lumina-bak`; an existing `.lumina-bak` is never
//   replaced, so it stays the file as it was before Lumina first wrote there;
// - new bytes land atomically (temp file in the same folder, fsync, rename) and are read back and
//   checksummed before the write counts as done;
// - copies never move and never overwrite a different file: a name clash with different content
//   gets a numbered name, a clash with identical content is already done;
// - nothing is written onto a card.
// The same rules as `Lumina/Sets/Core/SetsFileOps.swift`, which the package can't import.

public enum ExportFiles {
    public struct Failure: Error, CustomStringConvertible, Equatable {
        public let description: String
        public init(_ d: String) { description = d }
    }
    public enum CopyOutcome: Equatable, Sendable {
        case copied(URL), alreadyThere(URL), renamed(URL)
        public var url: URL { switch self { case .copied(let u), .alreadyThere(let u), .renamed(let u): return u } }
    }

    public static let backupSuffix = ".lumina-bak"
    private static let chunk = 4 << 20

    // MARK: Hashing

    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    public static func sha256(file url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let block = try h.read(upToCount: chunk), !block.isEmpty { hasher.update(data: block) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Write

    public static func backupURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + backupSuffix)
    }

    /// Writes `data` to `url` and reads it back. An existing file is first kept as
    /// `url.lumina-bak`, unless a backup is already there: that one is the original (Lightroom's
    /// sidecar before Lumina's first save), and a later save must not replace it with Lumina's own
    /// earlier output. Returns whether a backup was made. Identical bytes are not rewritten.
    @discardableResult
    public static func write(_ data: Data, to url: URL) throws -> Bool {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backedUp = false
        if fm.fileExists(atPath: url.path) {
            if isLocked(url) { throw Failure("locked") }
            let old = try Data(contentsOf: url)
            if old == data { return false }
            let bak = backupURL(for: url)
            if !fm.fileExists(atPath: bak.path) { try atomicWrite(old, to: bak); backedUp = true }
        }
        try atomicWrite(data, to: url)
        guard (try? Data(contentsOf: url)) == data else { throw Failure("verify failed") }
        return backedUp
    }

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).lumina-tmp-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: tmp) }
        // Not createFile: it only answers false, and the reason (disk full, read-only) has to reach the result.
        try Data().write(to: tmp, options: .withoutOverwriting)
        let h = try FileHandle(forWritingTo: tmp)
        do { try h.write(contentsOf: data); try h.synchronize(); try h.close() } catch { try? h.close(); throw error }
        // Re-read what landed before it replaces anything.
        guard try sha256(file: tmp) == sha256(data) else { throw Failure("verify failed") }
        if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: tmp) } else { try fm.moveItem(at: tmp, to: url) }
    }

    // MARK: Copy

    /// Copies `src` to `dst` (never moves). Streams with a running SHA-256, then re-reads the copy.
    public static func copyVerified(_ src: URL, to dst: URL) throws -> CopyOutcome {
        let fm = FileManager.default
        let srcHash = try sha256(file: src)                  // first: a missing original creates nothing
        let srcSize = (try? fm.attributesOfItem(atPath: src.path)[.size] as? NSNumber)?.int64Value
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        var target = dst, renamed = false, n = 2
        while fm.fileExists(atPath: target.path) {
            if try sha256(file: target) == srcHash { return .alreadyThere(target) }
            let stem = dst.deletingPathExtension().lastPathComponent, ext = dst.pathExtension
            target = dst.deletingLastPathComponent().appendingPathComponent("\(stem)-\(n)" + (ext.isEmpty ? "" : ".\(ext)"))
            renamed = true; n += 1
        }
        let tmp = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).lumina-tmp-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: tmp) }
        try Data().write(to: tmp, options: .withoutOverwriting)
        let r = try FileHandle(forReadingFrom: src), w = try FileHandle(forWritingTo: tmp)
        var hasher = SHA256()
        do {
            while let block = try r.read(upToCount: chunk), !block.isEmpty { hasher.update(data: block); try w.write(contentsOf: block) }
            try w.synchronize(); try w.close(); try r.close()
        } catch { try? w.close(); try? r.close(); throw error }
        let streamed = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard streamed == srcHash else { throw Failure("changed while it was being copied") }
        let size = (try? fm.attributesOfItem(atPath: tmp.path)[.size] as? NSNumber)?.int64Value
        guard size == srcSize, try sha256(file: tmp) == srcHash else { throw Failure("copy doesn’t match the original") }
        try fm.moveItem(at: tmp, to: target)                 // fails rather than replaces if a file appeared meanwhile
        return renamed ? .renamed(target) : .copied(target)
    }

    // MARK: Guards

    /// Finder's "Locked".
    public static func isLocked(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isUserImmutableKey]))?.isUserImmutable == true }

    /// A camera card: removable media, or any volume with a DCIM folder at its root. An external
    /// SSD without DCIM is a normal drive. A path that doesn't exist yet is judged by its nearest
    /// existing folder.
    public static func isCard(_ url: URL) -> Bool {
        var probe = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
        let v = try? probe.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeURLKey])
        if v?.volumeIsRemovable == true { return true }
        guard let root = v?.volume, root.path != "/" else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("DCIM").path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Bytes free on `url`'s volume, for the up-front space check.
    public static func freeBytes(at url: URL) -> Int64? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
        let v = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = v?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return v?.volumeAvailableCapacity.map(Int64.init)
    }

    /// Why a write failed, in two or three words.
    public static func reason(_ error: Error) -> String {
        if let f = error as? Failure { return f.description }
        if let x = error as? XMPSidecar.Unreadable { return x.description }
        var e: NSError? = error as NSError
        while let n = e {
            if n.domain == NSPOSIXErrorDomain {
                switch Int32(n.code) {
                case ENOSPC, EDQUOT: return "disk full"
                case EROFS: return "read-only"
                case EACCES, EPERM: return "locked"
                case ENOENT: return "missing"
                case ENOTDIR, EEXIST: return "can’t write there"
                default: break
                }
            }
            if n.domain == NSCocoaErrorDomain {
                switch n.code {
                case NSFileWriteOutOfSpaceError: return "disk full"
                case NSFileWriteVolumeReadOnlyError: return "read-only"
                case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return "locked"
                case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return "missing"
                default: break
                }
            }
            e = n.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return "failed"
    }
}
