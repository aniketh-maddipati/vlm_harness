import Foundation
import CryptoKit

// WP-8. The file-backed store: JSON in one directory, one file per shoot plus a "last" pointer.
//
//   <dir>/shoot-<name>-<hash>.json   {"v":1,"snapshot":{…},"extras":{…}}   (SnapshotFile)
//   <dir>/last.json                  {"v":1,"shootKey":"…"}
//
// Every write is atomic: a temp file in the same directory, flushed, then renamed over the
// target, so a reader (or a relaunch after a kill) sees the old file or the new one, never a
// part of one. Nothing outside the directory is read, written or removed.

public final class FilePersistence: SnapshotExtrasStore, @unchecked Sendable {
    public let directory: URL

    /// Where the app keeps its data when no `LUMINA_STORE_DIR` is given.
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Lumina/native", isDirectory: true)
    }

    enum WriteStage { case tempWritten, renamed }

    private let lock = NSLock()
    private var observers: [@Sendable (Snapshot) -> Void] = []
    private var lastKey: String?, lastKeyRead = false
    private var prepared = false
    private var reported: Set<String> = []
    private var _writes = 0
    /// Test seam: called inside a write, after the temp file is complete and after the rename.
    /// Throwing from `.tempWritten` is a write that failed half-way.
    var writeHook: ((WriteStage, URL) throws -> Void)?

    public init(directory: URL) { self.directory = directory.standardizedFileURL }

    /// Shoot files written so far (the coalescing tests count them).
    public var writeCount: Int { lock.withLock { _writes } }

    // MARK: PersistenceStore

    public func loadLast() throws -> Snapshot? {
        lock.withLock {
            guard let key = readLastKey() else { return nil }
            return read(key)?.snapshot
        }
    }

    public func load(shootKey: String) throws -> Snapshot? { lock.withLock { read(shootKey)?.snapshot } }

    public func loadWithExtras(shootKey: String) throws -> (snapshot: Snapshot, extras: SnapshotExtras)? {
        lock.withLock { read(shootKey).map { ($0.snapshot, $0.extras ?? SnapshotExtras()) } }
    }

    public func save(_ snapshot: Snapshot) throws {
        let kept = lock.withLock { read(snapshot.shootKey)?.extras }
        try save(snapshot, extras: kept ?? SnapshotExtras())
    }

    public func save(_ snapshot: Snapshot, extras: SnapshotExtras) throws {
        if Faults.shared.has(.storageFull) { throw PersistenceError.storageFull }
        let data = try SnapshotFile(snapshot: snapshot, extras: extras).encoded()
        let obs: [@Sendable (Snapshot) -> Void] = try lock.withLock {
            try write(data, to: url(for: snapshot.shootKey))
            _writes += 1
            if readLastKey() != snapshot.shootKey {
                try write(try JSONEncoder().encode(LastPointer(shootKey: snapshot.shootKey)), to: lastURL)
                lastKey = snapshot.shootKey
            }
            return observers
        }
        obs.forEach { $0(snapshot) }
    }

    public func clear(shootKey: String) throws {
        lock.withLock {
            unlink(url(for: shootKey).path)
            if readLastKey() == shootKey { unlink(lastURL.path); lastKey = nil }
        }
    }

    public func observe(_ onChange: @escaping @Sendable (Snapshot) -> Void) { lock.withLock { observers.append(onChange) } }

    // MARK: files

    var lastURL: URL { directory.appendingPathComponent("last.json") }

    /// A readable prefix for people, a hash for identity: keys can hold slashes, emoji or 220 characters.
    func url(for shootKey: String) -> URL {
        let slug = String(shootKey.unicodeScalars.map { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" ? Character($0) : "_" }.prefix(40))
        let hash = SHA256.hash(data: Data(shootKey.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("shoot-\(slug)-\(hash).json")
    }

    /// Lock held. Nil for a missing file. A file that can't be read or decoded is reported once
    /// through `ErrorFunnel`, set aside as `<name>.corrupt` (never deleted) and treated as empty.
    private func read(_ shootKey: String) -> SnapshotFile? {
        let u = url(for: shootKey)
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        do {
            let data = try Data(contentsOf: u)
            let f = try SnapshotFile.decode(data, shootKey: shootKey)
            guard f.snapshot.shootKey == shootKey else { return nil }
            if f.v > SnapshotFile.version { keepNewer(u, version: f.v) }
            return f
        } catch {
            report("stored shoot unreadable", u, error)
            setAside(u)
            return nil
        }
    }

    /// Lock held. The key in `last.json`. No file = no last shoot; a damaged one is reported,
    /// set aside, and answered once with the shoot file written most recently.
    private func readLastKey() -> String? {
        if lastKeyRead { return lastKey }
        lastKeyRead = true
        guard FileManager.default.fileExists(atPath: lastURL.path) else { return nil }
        if let d = try? Data(contentsOf: lastURL), let p = try? JSONDecoder().decode(LastPointer.self, from: d) { lastKey = p.shootKey; return lastKey }
        report("last-shoot pointer unreadable", lastURL, nil); setAside(lastURL)
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("shoot-") && $0.pathExtension == "json" }
        let newest = files.max { a, b in modified(a) < modified(b) }
        lastKey = newest.flatMap { try? Data(contentsOf: $0) }.flatMap { try? SnapshotFile.decode($0) }?.snapshot.shootKey
        return lastKey
    }

    private func modified(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }

    private func report(_ what: String, _ u: URL, _ error: Error?) {
        guard reported.insert(u.lastPathComponent).inserted else { return }
        ErrorFunnel.report("\(what) (\(u.lastPathComponent))", error)
    }

    private func setAside(_ u: URL) { rename(u.path, u.path + ".corrupt") }

    /// A newer build's file is about to be written over by this one: keep a copy, once.
    private func keepNewer(_ u: URL, version: Int) {
        let bak = URL(fileURLWithPath: u.path + ".v\(version).bak")
        if !FileManager.default.fileExists(atPath: bak.path) { try? FileManager.default.copyItem(at: u, to: bak) }
    }

    /// Lock held. Creates the directory and removes temp files a killed write left behind.
    private func prepare() throws {
        guard !prepared else { return }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw Self.map(error) }
        for f in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where f.hasPrefix(Self.tempPrefix) {
            unlink(directory.appendingPathComponent(f).path)
        }
        prepared = true
    }

    private static let tempPrefix = ".tmp-"

    /// Lock held. Temp file in the same directory → fsync → rename. On any failure the temp file
    /// is removed and the target is untouched.
    private func write(_ data: Data, to target: URL) throws {
        try prepare()
        let tmp = directory.appendingPathComponent(Self.tempPrefix + UUID().uuidString)
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw Self.posix(errno) }
        var fdOpen = true
        do {
            try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                var off = 0
                while off < buf.count {
                    let n = Darwin.write(fd, buf.baseAddress! + off, buf.count - off)
                    if n < 0 { if errno == EINTR { continue }; throw Self.posix(errno) }
                    off += n
                }
            }
            if fsync(fd) != 0 { throw Self.posix(errno) }
            try writeHook?(.tempWritten, tmp)
            fdOpen = false
            if close(fd) != 0 { throw Self.posix(errno) }
            if rename(tmp.path, target.path) != 0 { throw Self.posix(errno) }
            try? writeHook?(.renamed, target)
        } catch {
            if fdOpen { close(fd) }
            unlink(tmp.path)
            throw error
        }
    }

    /// ENOSPC and EDQUOT are "storage full" (R-71); anything else is an ordinary error.
    static func posix(_ code: Int32) -> Error {
        code == ENOSPC || code == EDQUOT ? PersistenceError.storageFull : NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    private static func map(_ error: Error) -> Error {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain, e.code == NSFileWriteOutOfSpaceError { return PersistenceError.storageFull }
        if e.domain == NSPOSIXErrorDomain, e.code == Int(ENOSPC) || e.code == Int(EDQUOT) { return PersistenceError.storageFull }
        if let u = e.userInfo[NSUnderlyingErrorKey] as? NSError, u.domain == NSPOSIXErrorDomain, u.code == Int(ENOSPC) || u.code == Int(EDQUOT) { return PersistenceError.storageFull }
        return error
    }
}
