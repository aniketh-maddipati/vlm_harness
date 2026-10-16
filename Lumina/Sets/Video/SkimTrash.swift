import Foundation

/// Move cut to Trash (STORAGE.md item 3, which absorbs FREESPACE.md): the clips the user marked cut, with their
/// Sony sidecars, go to the system Trash after his two clicks, so Put Back works; Skim never deletes and never
/// empties the Trash. Every move is noted in `skim/trash.json` in the container (where each file came from and
/// where it went), so Skim's own Put back can return them while they are still in the Trash.
///
/// Refused, in plain words, for a camera card, a read-only drive or anything under `PRIVATE/M4ROOT`
/// (`SkimDrive.refusal`), and for any path that leaves the folder the shoot was opened from.
nonisolated struct SkimTrash: Sendable {
    struct Moved: Codable, Equatable, Sendable {
        var shoot: String
        var rel: String
        var from: String
        var to: String
        var bytes: Int64
        var at: Double
    }

    /// One clip's answer: moved, put back or listed.
    struct Answer: Equatable, Sendable {
        var rel: String; var ok: Bool; var bytes: Int64; var why: String
        var json: [String: Any] { ["rel": rel, "ok": ok, "bytes": bytes, "why": why] }
    }

    let log: URL
    /// Held across each read, change and save of the note: Move and Put back run on their own tasks, and two that overlap
    /// would otherwise each save what they read and drop the other's entries (and Put back with them).
    private static let noteLock = NSLock()
    /// Moves one file to the Trash and answers where it went (`FileManager.trashItem` in the app).
    let trash: @Sendable (URL) throws -> URL

    init(log: URL, trash: @escaping @Sendable (URL) throws -> URL = SkimTrash.systemTrash) { self.log = log; self.trash = trash }

    static func systemTrash(_ url: URL) throws -> URL {
        #if canImport(Darwin)
        var out: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &out)
        guard let to = out as URL? else { throw CocoaError(.fileNoSuchFile) }
        return to
        #else
        throw CocoaError(.featureUnsupported)   // swift-corelibs-foundation has no Trash; the Linux tests pass their own
        #endif
    }

    /// A clip's path inside the opened folder, as the page knows it (relative, the folder's own name first or
    /// not), resolved and checked: a regular file inside `root`, nothing through `..` or a symlink out.
    static func resolve(root: URL, rel: String) -> URL? {
        var parts = rel.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, !rel.hasPrefix("/"), !parts.contains(".."), !parts.contains("."), !rel.contains("\0") else { return nil }
        if parts.count > 1, parts[0] == root.lastPathComponent, !FileManager.default.fileExists(atPath: root.appendingPathComponent(parts[0]).path) { parts.removeFirst() }
        let u = parts.reduce(root) { $0.appendingPathComponent($1) }
        let real = u.resolvingSymlinksInPath().standardizedFileURL.path, base = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard real.hasPrefix(base.hasSuffix("/") ? base : base + "/") else { return nil }
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &dir), !dir.boolValue else { return nil }
        return u
    }

    /// The folder a Skim pick came from: a folder picked alone is itself; clips (and folders) picked together share
    /// the deepest folder that holds them all. Nil for nothing picked.
    static func folder(of urls: [URL]) -> URL? {
        let dirs = urls.map { u -> [String] in
            var d: ObjCBool = false
            let isDir = FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
            return (urls.count == 1 && isDir ? u : u.deletingLastPathComponent()).standardizedFileURL.pathComponents
        }
        guard var common = dirs.first else { return nil }
        for d in dirs.dropFirst() {
            var n = 0
            while n < min(common.count, d.count) && common[n] == d[n] { n += 1 }
            common = Array(common.prefix(n))
        }
        guard !common.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: common), isDirectory: true)
    }

    /// A Sony clip's sidecars in the same folder: `C0001M01.XML` beside `C0001.MP4` (any case).
    static func companions(of file: URL) -> [URL] {
        let dir = file.deletingLastPathComponent(), stem = file.deletingPathExtension().lastPathComponent.uppercased()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { n in let u = n.uppercased(); return u.hasPrefix(stem + "M") && u.hasSuffix(".XML") && u.count == stem.count + 7 }
                    .sorted().map { dir.appendingPathComponent($0) }
    }

    static func size(_ u: URL) -> Int64 { Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }

    func all() -> [Moved] {
        guard let d = try? Data(contentsOf: log), d.count <= 8 << 20 else { return [] }
        return (try? JSONDecoder().decode([Moved].self, from: d)) ?? []
    }

    private func save(_ m: [Moved]) {
        guard let d = try? JSONEncoder().encode(Array(m.suffix(20_000))) else { return }
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: log, options: .atomic)
    }

    /// Moves the clips (and their sidecars) to the Trash. One answer per path asked for:
    /// Nothing moves when `refusal` is set.
    func move(root: URL, rels: [String], shoot: String, refusal: String?, now: Double = Date().timeIntervalSince1970 * 1000) -> [Answer] {
        if let refusal { return rels.map { Answer(rel: $0, ok: false, bytes: 0, why: refusal) } }
        Self.noteLock.lock(); defer { Self.noteLock.unlock() }
        var log = all(), out: [Answer] = []
        for rel in rels {
            guard let clip = Self.resolve(root: root, rel: rel) else { out.append(Answer(rel: rel, ok: false, bytes: 0, why: "not in the opened folder")); continue }
            if clip.path.uppercased().contains("/PRIVATE/M4ROOT/") {
                out.append(Answer(rel: rel, ok: false, bytes: 0, why: SkimDrive.refusal(path: clip.path, readOnly: false, card: true) ?? "on a card")); continue
            }
            let files = [clip] + Self.companions(of: clip)
            var moved: Int64 = 0, why: String?
            for f in files {
                let b = Self.size(f)
                do { let to = try trash(f); log.append(Moved(shoot: shoot, rel: rel, from: f.path, to: to.path, bytes: b, at: now)); moved += b }
                catch { if f == clip { why = "the Trash refused it"; break } }
            }
            out.append(Answer(rel: rel, ok: why == nil, bytes: moved, why: why ?? ""))
        }
        save(log)
        return out
    }

    /// Puts a shoot's moved files back where they were, while they are still in the Trash. One answer per clip.
    func putBack(shoot: String) -> [Answer] {
        Self.noteLock.lock(); defer { Self.noteLock.unlock() }
        var log = all(), keep: [Moved] = [], by: [String: (ok: Bool, bytes: Int64, why: String)] = [:]
        let fm = FileManager.default
        for m in log {
            guard m.shoot == shoot else { keep.append(m); continue }
            var r = by[m.rel] ?? (true, 0, "")
            if fm.fileExists(atPath: m.from) { r.ok = false; r.why = "a file is already where it was" ; keep.append(m) }
            else if !fm.fileExists(atPath: m.to) { r.ok = false; r.why = "not in the Trash any more" }
            else {
                do { try fm.moveItem(at: URL(fileURLWithPath: m.to), to: URL(fileURLWithPath: m.from)); r.bytes += m.bytes }
                catch { r.ok = false; r.why = "could not be put back"; keep.append(m) }
            }
            by[m.rel] = r
        }
        log = keep; save(log)
        return by.keys.sorted().map { k in Answer(rel: k, ok: by[k]!.ok, bytes: by[k]!.bytes, why: by[k]!.why) }
    }

    /// What this shoot has in the Trash now, by clip; files no longer in the Trash are left out.
    func listed(shoot: String) -> [Answer] {
        var sums: [String: Int64] = [:]
        for m in all() where m.shoot == shoot && FileManager.default.fileExists(atPath: m.to) { sums[m.rel, default: 0] += m.bytes }
        return sums.keys.sorted().map { Answer(rel: $0, ok: true, bytes: sums[$0]!, why: "") }
    }
}
