import CryptoKit
import Foundation

/// Every write Lumina makes goes through here. Rules (ROADMAP trust list, README export contract):
/// - a file being replaced is first kept as `<name>.lumina-bak`; an existing `.lumina-bak` is never
///   replaced, so it stays the file as it was before Lumina first wrote there;
/// - new bytes land atomically (temp file in the same folder, then rename) and are read back and
///   checksummed before the write counts as done; the temp file's name has a fixed length
///   (`tempName`), so it fits beside any name the folder can hold;
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

    /// Whether a file sits on a locked (immutable) file: Finder's "Locked". Writes refuse it.
    static func isLocked(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUserImmutableKey]))?.isUserImmutable == true
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

    /// Writes `data` to `url`. An existing file is first kept as `url.lumina-bak`, unless a backup
    /// is already there: that one is the original (e.g. Lightroom's sidecar before Lumina's first
    /// export) and a later export must not replace it with Lumina's own earlier output.
    @discardableResult
    static func write(_ data: Data, to url: URL) throws -> WriteResult {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backedUp = false
        if fm.fileExists(atPath: url.path) {
            let old = try Data(contentsOf: url)
            if old == data { return WriteResult(backedUp: false) }            // nothing to change
            if !fm.fileExists(atPath: backupURL(for: url).path) {
                try atomicWrite(old, to: backupURL(for: url))
                backedUp = true
            }
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

    // MARK: Temp names

    /// Every temp file Lumina writes is `.lumina-tmp-<tag>-<8 hex>`, in the folder of the file it
    /// becomes: 37 bytes whatever that file is called. (It used to be `.<name>.lumina-tmp-<8 hex>`,
    /// 21 bytes longer than the name, so a name over 234 bytes could not be written at all.)
    /// `<tag>` is `tempTag(for:)` of the final name, which is how the launch after a crash knows a
    /// leftover is Lumina's and whose it was (`SetsExportJournal.recover`).
    static let tempPrefix = ".lumina-tmp-"

    /// 16 hex characters from the SHA-256 of a file name.
    static func tempTag(for name: String) -> String { String(sha256(Data(name.utf8)).prefix(16)) }

    /// A new temp name for the file that will be called `name`.
    static func tempName(for name: String) -> String {
        tempPrefix + tempTag(for: name) + "-" + String(UUID().uuidString.prefix(8))
    }

    /// The tag in `file` when it is exactly a temp name as `tempName` makes them, else nil: a file
    /// that only looks similar (another length, other characters, anything after) is not Lumina's.
    static func tempTag(of file: String) -> String? {
        guard file.hasPrefix(tempPrefix) else { return nil }
        let parts = file.dropFirst(tempPrefix.count).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].utf8.count == 16, parts[1].utf8.count == 8,
              parts[0].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              parts[1].utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        return String(parts[0])
    }

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(tempName(for: url.lastPathComponent))
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Not createFile: it only answers false, and the reason (disk full, read-only, no permission)
        // has to reach the result list.
        try Data().write(to: tmp, options: .withoutOverwriting)
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

    // MARK: Sidecars (SAFETY.md 1)

    /// Why one sidecar wasn't written, in the page's words ("DSC03311 · locked").
    struct SidecarError: Error, Equatable {
        let name: String
        let reason: String
    }

    /// What Save says when a sidecar is no longer the file its merge was based on.
    static let sidecarChanged = "changed on disk"
    /// The base of a sidecar that isn't there.
    static let noSidecar = "none"
    /// The largest sidecar Lumina reads or replaces. The listing skips bigger ones without reading
    /// them (`SetsIngest.Limits`); Save leaves them as they are and says so, rather than reading a
    /// file of any size to merge into it.
    static let sidecarMaxBytes = 1 << 20
    static let sidecarTooBig = "over 1 MB"
    /// What Save says for a sidecar that is there but is not UTF-8 text (Latin-1, UTF-16, binary):
    /// nothing can be merged into it, so it is left exactly as it is. The page's own word for a
    /// file it can't read; the final wording is a design ask (DESIGN-ASKS, "a sidecar Lumina can't read").
    static let sidecarUnreadable = "unreadable"
    /// A file (or the `.lumina-bak` of the file it would replace) whose name the disk refuses as too long.
    static let nameTooLong = "name too long"

    /// Whether the sidecar at `url` is over `sidecarMaxBytes`, from its size alone.
    private static func tooBig(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > sidecarMaxBytes
    }

    /// What a merge is based on: the SHA-256 of the sidecar's bytes as they are on disk now, or
    /// `noSidecar` when there is no file.
    static func sidecarBase(_ url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return noSidecar }
        return sha256(try Data(contentsOf: url))
    }

    /// Where `rel` ("sub/DSC03311.xmp") lands inside `root`. Only a `.xmp` name that stays inside
    /// `root` is accepted, so nothing else in the folder (a RAW above all) can be read or written.
    private static func sidecarURL(rel: String, root: URL) throws -> (url: URL, parent: URL, stem: String) {
        let name = (rel as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        guard !rel.hasPrefix("/"), !rel.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }),
              (rel as NSString).pathExtension.lowercased() == "xmp" else { throw SidecarError(name: stem, reason: "refused") }
        let url = root.appendingPathComponent(rel).standardizedFileURL
        let parent = url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path) else { throw SidecarError(name: stem, reason: "missing") }
        // Compared with symlinks resolved on the folder (which exists), so a linked subfolder can't
        // lead out of the shoot; the sidecar itself must not be a link.
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let parentPath = parent.resolvingSymlinksInPath().path
        guard parentPath == rootPath || parentPath.hasPrefix(rootPath + "/") else { throw SidecarError(name: stem, reason: "refused") }
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { throw SidecarError(name: stem, reason: "refused") }
        return (url, parent, stem)
    }

    /// One sidecar as it is on disk now, for Save's merge: its text (nil when there is no file, or
    /// when it isn't UTF-8: the listing names that one in `unreadableXmp`, and `writeSidecar`
    /// refuses to replace it) and its base, from the same bytes.
    /// Save reads this right before it merges: the text from the open can be hours old, and
    /// another app (Lightroom) may have written the file since.
    static func readSidecar(rel: String, root: URL) throws -> (text: String?, base: String) {
        let (url, _, stem) = try sidecarURL(rel: rel, root: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, noSidecar) }
        if tooBig(url) { throw SidecarError(name: stem, reason: sidecarTooBig) }
        do {
            let data = try Data(contentsOf: url)
            return (String(data: data, encoding: .utf8), sha256(data))
        } catch {
            throw SidecarError(name: stem, reason: reason(error))
        }
    }

    /// Writes one .xmp sidecar INTO the shoot folder, next to its RAW: `rel` is the path inside
    /// `root` ("sub/DSC03311.xmp"). Only a `.xmp` name that stays inside `root` is accepted, so
    /// nothing else in the folder (a RAW above all) can be written. An existing sidecar is kept as
    /// `.lumina-bak` first; the new bytes land atomically (temp file in the same folder, fsync,
    /// rename) and the file is read back and compared after the rename. Refused on a card, and
    /// "missing" when its RAW is no longer beside it (renamed, moved or deleted since the read).
    ///
    /// `base` is what `data` was merged from (`sidecarBase`: the SHA-256 of the sidecar then, or
    /// `noSidecar`). When the file on disk is no longer that, another app wrote it in between and
    /// `data` carries its older settings: nothing is written and the error says "changed on disk".
    /// The caller reads again and merges again. nil skips the check (a caller that merged nothing).
    /// The check and the rename are not one step: what is left is the instant between them.
    ///
    /// A sidecar on disk that is not UTF-8 text is never replaced, whatever `base` says: the page
    /// could not read it, so `data` is a fresh ratings-only sidecar and the other app's settings
    /// would survive only in the backup. It is left as it is and the error says "unreadable".
    @discardableResult
    static func writeSidecar(_ data: Data, rel: String, root: URL, base: String? = nil) throws -> WriteResult {
        let (url, parent, stem) = try sidecarURL(rel: rel, root: root)
        if isCard(root) { throw SidecarError(name: stem, reason: "on the card") }
        if isLocked(url) { throw SidecarError(name: stem, reason: "locked") }
        guard hasRaw(named: stem, in: parent) else { throw SidecarError(name: stem, reason: "missing") }
        if tooBig(url) { throw SidecarError(name: stem, reason: sidecarTooBig) }
        if let old = try? Data(contentsOf: url), String(data: old, encoding: .utf8) == nil {
            throw SidecarError(name: stem, reason: sidecarUnreadable)
        }
        do {
            // A file that already holds these bytes has nothing to lose, whatever they were merged from.
            if let base, try sidecarBase(url) != base, (try? Data(contentsOf: url)) != data {
                throw SidecarError(name: stem, reason: sidecarChanged)
            }
            let r = try write(data, to: url)
            guard (try? Data(contentsOf: url)) == data else { throw SidecarError(name: stem, reason: "verify failed") }
            return r
        } catch let e as SidecarError {
            throw e
        } catch {
            throw SidecarError(name: stem, reason: reason(error))
        }
    }

    /// Whether `folder` holds an ARW called `stem` (any case of the extension). A sidecar without
    /// its RAW is read by nothing, and saying "saved" for it would be wrong (SAFETY.md 6).
    static func hasRaw(named stem: String, in folder: URL) -> Bool {
        let fm = FileManager.default
        for ext in ["ARW", "arw"] where fm.fileExists(atPath: folder.appendingPathComponent(stem + "." + ext).path) { return true }
        return ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).contains {
            ($0 as NSString).pathExtension.lowercased() == "arw" && ($0 as NSString).deletingPathExtension == stem
        }
    }

    /// A write error in two or three words.
    static func reason(_ error: Error) -> String {
        let ns = error as NSError
        // The errno under a Cocoa error: an NSError on Darwin, a POSIXError value in swift-foundation (Linux).
        let under = ns.userInfo[NSUnderlyingErrorKey]
        let posix = (under as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? Int32($0.code) : nil }
            ?? (under as? POSIXError).map { $0.code.rawValue }
            ?? (ns.domain == NSPOSIXErrorDomain ? Int32(ns.code) : nil)
        switch posix {
        case ENAMETOOLONG: return nameTooLong
        case ENOSPC, EDQUOT: return "disk full"
        case EROFS: return "read-only"
        case EACCES, EPERM: return "locked"
        case ENOENT: return "missing"
        default: break
        }
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileWriteOutOfSpaceError: return "disk full"
            case NSFileWriteVolumeReadOnlyError: return "read-only"
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return "locked"
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return "missing"
            // What Foundation makes of ENAMETOOLONG when the errno itself is not passed on.
            case CocoaError.Code.fileWriteInvalidFileName.rawValue, CocoaError.Code.fileReadInvalidFileName.rawValue: return nameTooLong
            default: break
            }
        }
        return "failed"
    }

    // MARK: Copy

    /// Copies `src` to `dst` (never moves). Streams with a running SHA-256, then re-reads the copy.
    static func copyVerified(_ src: URL, to dst: URL) throws -> CopyOutcome {
        let fm = FileManager.default
        let srcHash = try sha256(file: src)                  // first: a missing original creates nothing
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
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
        // Tagged with the name asked for, not the numbered one it may land under: recovery knows the
        // planned names only (`SetsExportJournal.recover`).
        let tmp = target.deletingLastPathComponent().appendingPathComponent(tempName(for: dst.lastPathComponent))
        defer { try? fm.removeItem(at: tmp) }
        try Data().write(to: tmp, options: .withoutOverwriting)       // throws with the reason (disk full, read-only, …)
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
