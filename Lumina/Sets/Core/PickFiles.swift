import Foundation

/// Pick's Handoff file view (`window.lumina.files`, Prompt 27): the drives and folders Lumina may look inside, listed
/// without opening anything; a search over folder names that answers a page at a time; copies of a photo (its RAW and its
/// sidecar) into a folder, each read back and compared; a folder renamed; what Handoff saved, checked and kept in a note
/// so only those files can go to the Trash; and Save to (next to each RAW, a folder, or ask each time).
/// Lumina copies, never moves (ruled 2026-10-14): nothing here moves a photo. Foundation only.
nonisolated enum PickFiles {
    /// Whether Lumina may look inside a drive: the whole drive, some folders on it, or none. The page reads it as
    /// `granted`: `true`, `"some"` or `false`.
    enum Access: Sendable {
        case all, some, none
        var json: Any { self == .all ? true : self == .some ? "some" : false }
    }
    static func access(drive: String, roots: [URL]) -> Access {
        if roots.contains(where: { SkimPlaces.inside(drive, root: $0) }) { return .all }
        return rootsOn(drive: drive, roots: roots).isEmpty ? .none : .some
    }

    /// The folders Lumina may look inside that are on `drive` (not the drive itself), each once, by name. A folder inside
    /// another one listed is left out: the tree reaches it through its parent.
    static func rootsOn(drive: String, roots: [URL]) -> [URL] {
        let d = URL(fileURLWithPath: drive, isDirectory: true)
        let on = roots.map { $0.standardizedFileURL }.filter { r in
            let p = r.resolvingSymlinksInPath().path, dp = d.standardizedFileURL.resolvingSymlinksInPath().path
            return p != dp && SkimPlaces.inside(r.path, root: d) && (dp != "/" || !p.hasPrefix("/Volumes/"))
        }
        var seen = Set<String>(), out: [URL] = []
        for r in on where !on.contains(where: { $0.path != r.path && SkimPlaces.inside(r.path, root: $0) }) {
            if seen.insert(r.path).inserted { out.append(r) }
        }
        return out.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static let maxEntries = 2000

    /// What is directly inside `dir`: folders first (each `dirs: true` without opening it, so a listing costs one directory
    /// read; the page says "Empty" when it unfurls one with nothing inside), then files with their sizes. Hidden names and
    /// links are left out; a package (an .app, a library) is a file. nil when the folder can't be read.
    struct Entry: Equatable, Sendable {
        var name: String; var path: String; var dir: Bool; var bytes: Int64
        var json: [String: Any] { dir ? ["name": name, "path": path, "dirs": true] : ["name": name, "path": path, "file": true, "bytes": bytes] }
    }
    static func list(_ dir: URL) -> [Entry]? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let names = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        var dirs: [(String, String)] = [], files: [(String, String, Int64)] = []
        for u in names {
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isSymbolicLink == true { continue }
            if v?.isDirectory == true && v?.isPackage != true { dirs.append((u.lastPathComponent, u.path)) }
            else { files.append((u.lastPathComponent, u.path, Int64(v?.fileSize ?? 0))) }
            if dirs.count + files.count >= maxEntries { break }
        }
        dirs.sort { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        files.sort { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        return dirs.map { Entry(name: $0.0, path: $0.1, dir: true, bytes: 0) } + files.map { Entry(name: $0.0, path: $0.1, dir: false, bytes: $0.2) }
    }

    /// The folders of a drive Lumina may look into only in part: the folders let in on it.
    static func listSome(_ roots: [URL]) -> [[String: Any]] {
        roots.map { ["name": FileManager.default.displayName(atPath: $0.path), "path": $0.path, "dirs": true] }
    }

    // MARK: Search

    /// The file view's search (`dirSearch`): folders whose name holds the query (any case, accents ignored), under the
    /// folders Lumina may look inside, breadth first so the shallow ones come first, a page at a time. Hidden folders,
    /// packages and links are not entered; only names are read. The search keeps its place between pages.
    nonisolated final class Search: @unchecked Sendable {
        let query: [String]
        private var queue: [(URL, Int)] = []
        private var head = 0
        private var seen = Set<String>()
        private var ready: [[String: String]] = []   // found but not yet answered: a page ends at `limit` mid-folder
        private let lock = NSLock()
        static let maxDepth = 10, maxFolders = 50_000

        init(_ q: String, roots: [URL]) {
            query = SkimPlaces.words(q)
            for r in roots { let u = r.standardizedFileURL; if seen.insert(u.path).inserted { queue.append((u, 0)) } }
        }

        /// The next hits, at most `limit`, read for at most `budget` seconds; `done` when nothing is left to read; `at` is
        /// the folder being read when the page ended.
        func next(limit: Int, budget: TimeInterval, cancelled: () -> Bool = { false }) -> (hits: [[String: String]], done: Bool, at: String) {
            lock.lock(); defer { lock.unlock() }
            guard !query.isEmpty else { return ([], true, "") }
            let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
            let end = Date().addingTimeInterval(budget)
            var at = ""
            while head < queue.count, ready.count < limit, Date() < end, seen.count < Self.maxFolders, !cancelled() {
                let (dir, depth) = queue[head]; head += 1
                at = dir.lastPathComponent
                guard let names = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
                for u in names.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                    let v = try? u.resourceValues(forKeys: Set(keys))
                    guard v?.isDirectory == true, v?.isPackage != true, v?.isSymbolicLink != true,
                          !SkimPlaces.packageExtensions.contains(u.pathExtension.lowercased()) else { continue }
                    let p = u.standardizedFileURL
                    guard seen.insert(p.path).inserted else { continue }
                    let folded = SkimPlaces.words(u.lastPathComponent).joined(separator: " ")
                    if query.allSatisfy({ folded.contains($0) }) { ready.append(["name": u.lastPathComponent, "path": p.path]) }
                    if depth + 1 < Self.maxDepth { queue.append((p, depth + 1)) }
                }
            }
            let hits = Array(ready.prefix(max(0, limit)))
            ready.removeFirst(hits.count)
            let done = ready.isEmpty && (head >= queue.count || seen.count >= Self.maxFolders)
            return (hits, done, done ? "" : at)
        }
    }

    // MARK: Copies

    /// A photo's sidecar beside it (`DSC0001.xmp` or `.XMP`), when there is one.
    static func sidecar(of raw: URL) -> URL? {
        let dir = raw.deletingLastPathComponent(), stem = raw.deletingPathExtension().lastPathComponent
        for ext in ["xmp", "XMP"] {
            let u = dir.appendingPathComponent(stem + "." + ext)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// The first free name for `name` in `dir`: the name itself, else "stem 2.ext", "stem 3.ext", … A sidecar must follow
    /// the RAW's stem, so the name is free only when no file with that stem and any of `alsoFree`'s extensions is there.
    static func freeName(_ name: String, in dir: URL, alsoFree: [String] = []) -> String {
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension, fm = FileManager.default
        func free(_ s: String) -> Bool {
            !fm.fileExists(atPath: dir.appendingPathComponent(ext.isEmpty ? s : s + "." + ext).path)
                && !alsoFree.contains { fm.fileExists(atPath: dir.appendingPathComponent(s + "." + $0).path) }
        }
        if free(stem) { return name }
        var n = 2
        while !free("\(stem) \(n)") { n += 1 }
        return ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
    }

    /// One photo copied into `dir`: the RAW, then its sidecar under the same new stem, each streamed with a running SHA-256
    /// and read back before it counts (`SetsFileOps.copyVerified`). Never over a file: a name already there gets " 2".
    /// Answers the RAW copy's path and every file made (for Undo), or why not. A copy that failed half way removes what it made.
    static func copy(raw: URL, into dir: URL) -> (to: String?, made: [String], why: String) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: raw.path, isDirectory: &isDir), !isDir.boolValue else { return (nil, [], "The photo is not there any more.") }
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return (nil, [], "That folder is not there any more.") }
        if SetsFileOps.isCard(dir) { return (nil, [], "Lumina never writes to a card.") }
        if raw.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == dir.standardizedFileURL.resolvingSymlinksInPath().path {
            return (nil, [], "Already in that folder.")
        }
        let side = sidecar(of: raw)
        let name = freeName(raw.lastPathComponent, in: dir, alsoFree: side == nil ? [] : ["xmp", "XMP"])
        var made: [String] = []
        do {
            let r = dir.appendingPathComponent(name)
            switch try SetsFileOps.copyVerified(raw, to: r) {
            case .copied(let u), .renamed(let u): made.append(u.path)
            case .alreadyThere: return (nil, [], "Already in that folder.")
            }
            if let side {
                let s = dir.appendingPathComponent((name as NSString).deletingPathExtension + "." + side.pathExtension)
                switch try SetsFileOps.copyVerified(side, to: s) {
                case .copied(let u), .renamed(let u): made.append(u.path)
                case .alreadyThere: break
                }
            }
            return (made.first, made, "")
        } catch {
            for p in made { try? fm.removeItem(atPath: p) }
            return (nil, [], "Not copied: " + SetsFileOps.reason(error) + ".")
        }
    }

    // MARK: Rename

    /// Renames a folder in place (same parent, a plain name, never over anything). Refused for a root Lumina was let into,
    /// a folder on a card, a folder holding the open shoot, and anything that is not a folder.
    static func rename(_ path: String, to typed: String, roots: [URL], shoot: URL?) -> (ok: Bool, path: String, why: String) {
        let fm = FileManager.default, u = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard let clean = SkimPlaces.folderName(typed) else { return (false, "", "That is not a folder name.") }
        guard roots.contains(where: { SkimPlaces.inside(u.path, root: $0) }) else { return (false, "", "Lumina has no access to that folder.") }
        if roots.contains(where: { $0.standardizedFileURL.resolvingSymlinksInPath().path == u.resolvingSymlinksInPath().path }) {
            return (false, "", "That folder is one Lumina was let into; rename it in Finder.")
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue,
              (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true else { return (false, "", "That folder is not there any more.") }
        if SetsFileOps.isCard(u) { return (false, "", "Lumina never changes a card.") }
        if let shoot, SkimPlaces.inside(shoot.path, root: u) { return (false, "", "That folder holds the open shoot.") }
        let to = u.deletingLastPathComponent().appendingPathComponent(clean, isDirectory: true)
        if to.path == u.path { return (true, u.path, "") }
        // A change of case only is the same name to a case-insensitive disk: it is renamed through a free name.
        let caseOnly = to.path.lowercased() == u.path.lowercased()
        if !caseOnly && fm.fileExists(atPath: to.path) { return (false, "", "A folder named “\(clean)” is already there.") }
        do {
            if caseOnly {
                let mid = u.deletingLastPathComponent().appendingPathComponent(".lumina-rename-\(UUID().uuidString.prefix(8))")
                try fm.moveItem(at: u, to: mid); try fm.moveItem(at: mid, to: to)
            } else {
                try fm.moveItem(at: u, to: to)
            }
            return (true, to.path, "")
        } catch { return (false, "", "Not renamed: " + SetsFileOps.reason(error) + ".") }
    }

    // MARK: Saved files

    /// One Saved files entry as it is on disk now: `missing` when none of its files is there, `edited` when one changed
    /// after `at` (milliseconds since 1970; a second of slack for the write itself), else `ok`.
    static func check(_ paths: [String], at: Double) -> String {
        let fm = FileManager.default
        var any = false
        for p in paths where !p.isEmpty {
            guard let a = try? fm.attributesOfItem(atPath: p) else { continue }
            any = true
            if let m = a[.modificationDate] as? Date, m.timeIntervalSince1970 * 1000 > at + 1000 { return "edited" }
        }
        return any ? "ok" : "missing"
    }

    /// Writes one sidecar into a folder that is not the shoot's (Save to): `rel` stays inside `dir` and ends in `.xmp`; the
    /// folders it names are made. An existing file is kept as `.lumina-bak` first, the bytes land atomically and are read
    /// back. Refused on a card.
    @discardableResult
    static func writeSidecar(_ data: Data, rel: String, into dir: URL) throws -> SetsFileOps.WriteResult {
        let stem = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
        guard !rel.hasPrefix("/"), !rel.utf8.contains(0), !rel.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }),
              (rel as NSString).pathExtension.lowercased() == "xmp" else { throw SetsFileOps.SidecarError(name: stem, reason: "refused") }
        if SetsFileOps.isCard(dir) { throw SetsFileOps.SidecarError(name: stem, reason: "on the card") }
        let url = dir.appendingPathComponent(rel).standardizedFileURL, parent = url.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true) }
        catch { throw SetsFileOps.SidecarError(name: stem, reason: SetsFileOps.reason(error)) }
        let root = dir.standardizedFileURL.resolvingSymlinksInPath().path, at = parent.resolvingSymlinksInPath().path
        guard at == root || at.hasPrefix(root + "/") else { throw SetsFileOps.SidecarError(name: stem, reason: "refused") }
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { throw SetsFileOps.SidecarError(name: stem, reason: "refused") }
        if SetsFileOps.isLocked(url) { throw SetsFileOps.SidecarError(name: stem, reason: "locked") }
        do {
            let r = try SetsFileOps.write(data, to: url)
            guard (try? Data(contentsOf: url)) == data else { throw SetsFileOps.SidecarError(name: stem, reason: "verify failed") }
            return r
        } catch let e as SetsFileOps.SidecarError { throw e }
        catch { throw SetsFileOps.SidecarError(name: stem, reason: SetsFileOps.reason(error)) }
    }

    /// Handoff's note of the files it wrote (sidecars, JPEGs, copies), in the container: only these may go to the Trash
    /// from the page. Newest last, at most `cap`.
    struct Written: Sendable {
        let file: URL
        static let cap = 50_000
        func all() -> Set<String> {
            guard let d = try? Data(contentsOf: file), d.count <= 32 << 20, let a = try? JSONDecoder().decode([String].self, from: d) else { return [] }
            return Set(a)
        }
        func add(_ paths: [String]) {
            guard !paths.isEmpty else { return }
            let old = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            let new = Set(paths)
            var a = old.filter { !new.contains($0) } + paths
            if a.count > Self.cap { a.removeFirst(a.count - Self.cap) }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(a).write(to: file, options: .atomic)
        }
    }

    /// Save to, kept in the container: next to each RAW (the default), a folder (a security-scoped bookmark), or ask each time.
    struct SaveTo: Codable, Equatable, Sendable {
        var ask: Bool = false
        var bookmark: Data?
        var path: String?
    }
    struct SaveToStore: Sendable {
        let file: URL
        func get() -> SaveTo {
            guard let d = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(SaveTo.self, from: d) else { return SaveTo() }
            return s
        }
        func set(_ s: SaveTo) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(s).write(to: file, options: .atomic)
        }
    }
}
