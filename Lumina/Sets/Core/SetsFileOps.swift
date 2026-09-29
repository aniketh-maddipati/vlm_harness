import CryptoKit
import Foundation

/// Every write Lumina makes goes through here. Rules (ROADMAP trust list, README export contract):
/// - a file being replaced is first kept as `<name>.lumina-bak`;
/// - new bytes land atomically (temp file in the same folder, then rename) and are read back and
///   checksummed before the write counts as done;
/// - copies never move and never overwrite a different file: a name clash with different content
///   gets a numbered name, a clash with identical content is already done;
/// - nothing is written onto the source card or inside the source folder.
nonisolated enum SetsFileOps {
    struct WriteResult: Equatable { let backedUp: Bool }
    enum CopyOutcome: Equatable { case copied(URL), alreadyThere(URL), renamed(URL) }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    static let backupSuffix = ".lumina-bak"
    private static let chunk = 4 << 20

    // MARK: Hashing

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(file url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let block = try h.read(upToCount: chunk), !block.isEmpty { hasher.update(data: block) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Write

    /// Writes `data` to `url`. An existing file is first kept as `url.lumina-bak`.
    @discardableResult
    static func write(_ data: Data, to url: URL) throws -> WriteResult {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backedUp = false
        if fm.fileExists(atPath: url.path) {
            let old = try Data(contentsOf: url)
            if old == data { return WriteResult(backedUp: false) }            // nothing to change
            try atomicWrite(old, to: backupURL(for: url))
            backedUp = true
        }
        try atomicWrite(data, to: url)
        return WriteResult(backedUp: backedUp)
    }

    /// Atomic, verified write with no backup — only for Lumina's own files (journal, session store).
    static func replaceOwn(_ data: Data, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try atomicWrite(data, to: url)
    }

    static func backupURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + backupSuffix)
    }

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).lumina-tmp-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard FileManager.default.createFile(atPath: tmp.path, contents: nil) else {
            throw Failure("can't write in \(dir.path)")
        }
        let h = try FileHandle(forWritingTo: tmp)
        do {
            try h.write(contentsOf: data)
            try h.synchronize()
            try h.close()
        } catch { try? h.close(); throw error }
        // Re-read what landed before it replaces anything.
        guard try sha256(file: tmp) == sha256(data) else { throw Failure("verify failed writing \(url.lastPathComponent)") }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    // MARK: Copy

    /// Copies `src` to `dst` (never moves). Streams with a running SHA-256, then re-reads the copy.
    static func copyVerified(_ src: URL, to dst: URL) throws -> CopyOutcome {
        let fm = FileManager.default
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        let srcHash = try sha256(file: src)
        var target = dst
        var renamed = false
        var n = 2
        while fm.fileExists(atPath: target.path) {
            if try sha256(file: target) == srcHash { return .alreadyThere(target) }
            let stem = dst.deletingPathExtension().lastPathComponent, ext = dst.pathExtension
            target = dst.deletingLastPathComponent().appendingPathComponent("\(stem)-\(n)" + (ext.isEmpty ? "" : ".\(ext)"))
            renamed = true
            n += 1
        }
        let tmp = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).lumina-tmp-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: tmp) }
        guard fm.createFile(atPath: tmp.path, contents: nil) else { throw Failure("can't write in \(target.deletingLastPathComponent().path)") }
        let r = try FileHandle(forReadingFrom: src), w = try FileHandle(forWritingTo: tmp)
        var hasher = SHA256()
        do {
            while let block = try r.read(upToCount: chunk), !block.isEmpty {
                hasher.update(data: block)
                try w.write(contentsOf: block)
            }
            try w.synchronize()
            try w.close(); try r.close()
        } catch { try? w.close(); try? r.close(); throw error }
        let streamed = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard streamed == srcHash else { throw Failure("\(src.lastPathComponent) changed while it was being copied") }
        guard try sha256(file: tmp) == srcHash else { throw Failure("copy of \(src.lastPathComponent) doesn't match the original") }
        try fm.moveItem(at: tmp, to: target)
        return renamed ? .renamed(target) : .copied(target)
    }

    // MARK: Destination guard

    /// A destination is refused when it is on the same volume as a source that lives on removable
    /// media (the card), or when it is inside (or equal to) any source folder.
    static func refusal(destination: URL, sources: [URL]) -> String? {
        let dest = destination.standardizedFileURL.resolvingSymlinksInPath()
        for src in sources {
            let s = src.standardizedFileURL.resolvingSymlinksInPath()
            if dest.path == s.path || dest.path.hasPrefix(s.path + "/") {
                return "Pick a folder outside \(s.lastPathComponent). Lumina never writes into the folder it's culling."
            }
            if isCard(s), volumeID(dest) != nil, volumeID(dest) == volumeID(s) {
                return "Pick a folder that isn't on the card. Lumina never writes to the card."
            }
        }
        return nil
    }

    static func volumeID(_ url: URL) -> String? {
        let v = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeURLKey])
        return v?.volumeUUIDString ?? v?.volume?.path
    }

    /// A camera card: removable media, or any volume with a DCIM folder at its root. An external
    /// SSD without DCIM is a normal drive and may take exports.
    static func isCard(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeURLKey])
        if v?.volumeIsRemovable == true { return true }
        guard let root = v?.volume, root.path != "/" else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("DCIM").path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Bytes free at `url`'s volume, for the up-front disk-space check.
    static func freeBytes(at url: URL) -> Int64? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
        let v = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = v?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return v?.volumeAvailableCapacity.map(Int64.init)
    }
}
