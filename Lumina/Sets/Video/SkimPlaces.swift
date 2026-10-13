import Foundation

/// Export's workshop (the folder tree): the drives mounted on this Mac, the folders the user has let Skim into, and the
/// folders inside those. macOS lets a sandboxed app name a drive but not look inside it until the user picks it (or a
/// folder on it) in the folder panel once; each folder picked is kept as a security-scoped bookmark in
/// `skim/places.json`. Listing shows folders (and, for the file view, files with their sizes; nothing hidden) and never leaves a granted folder; a new
/// folder is made only inside one, with a plain name. Nothing here moves, renames or deletes. Foundation only.
nonisolated struct SkimPlaces: Sendable {
    struct Place: Codable, Equatable, Sendable {
        var bookmark: Data
        var path: String
    }

    /// One folder in the tree: its name, its path and whether it has folders inside (so the tree shows a chevron).
    struct Folder: Equatable, Sendable {
        var name: String; var path: String; var dirs: Bool
        var json: [String: Any] { ["name": name, "path": path, "dirs": dirs] }
    }

    static let maxListed = 500
    let file: URL

    func all() -> [Place] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([Place].self, from: data)) ?? []
    }

    @discardableResult
    func save(_ places: [Place]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(places).write(to: file, options: .atomic)
            return true
        } catch { return false }
    }

    /// Keeps a folder (replacing one kept at the same path), at most 24, the newest first.
    @discardableResult
    func add(_ p: Place) -> Bool { save(Array(([p] + all().filter { $0.path != p.path }).prefix(24))) }

    @discardableResult
    func remove(path: String) -> Bool { save(all().filter { $0.path != path }) }

    /// Whether `path` is `root` or inside it, with symlinks resolved on both sides.
    static func inside(_ path: String, root: URL) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let r = root.standardizedFileURL.resolvingSymlinksInPath().path
        return p == r || p.hasPrefix(r.hasSuffix("/") ? r : r + "/")
    }

    /// The folders directly inside `dir`, by name; hidden ones, packages (an .fcpbundle, an .app) and links are left out.
    static func folders(in dir: URL) -> [Folder]? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return nil }
        var out: [Folder] = []
        for u in names {
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
            guard v?.isDirectory == true, v?.isPackage != true, v?.isSymbolicLink != true else { continue }
            out.append(Folder(name: u.lastPathComponent, path: u.path, dirs: hasInside(u, folders: true)))
            if out.count >= maxListed { break }
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether `dir` has anything (with `folders`, a folder) inside, hidden ones aside. The listing is read lazily and stops at
    /// the first match, or after `scanLimit` names (then the answer is yes), so a folder of thousands of clips costs one
    /// directory read, not a full listing per row.
    static let scanLimit = 400
    static func hasInside(_ dir: URL, folders: Bool) -> Bool {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: folders ? [.isDirectoryKey, .isPackageKey] : [],
                                                     options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]) else { return false }
        var n = 0
        while let u = e.nextObject() as? URL {
            if !folders { return true }
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if v?.isDirectory == true, v?.isPackage != true { return true }
            n += 1
            if n >= scanLimit { return true }
        }
        return false
    }

    /// One entry of the workshop's file view: a folder (with whether it has folders or files inside) or a file with its size.
    struct Entry: Equatable, Sendable {
        var name: String; var path: String; var dir: Bool; var dirs: Bool; var bytes: Int64
        var json: [String: Any] { dir ? ["name": name, "path": path, "dirs": dirs] : ["name": name, "path": path, "file": true, "bytes": bytes] }
    }
    static let maxEntries = 2000

    /// What is directly inside `dir`, folders first, then files, each by name; hidden ones and links are left out, a
    /// package (an .fcpbundle, an .app) is listed as a file. Nothing is opened or read beyond the folder's listing.
    static func entries(in dir: URL) -> [Entry]? {
        let fm = FileManager.default, keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let names = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        var dirs: [Entry] = [], files: [Entry] = []
        for u in names {
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isSymbolicLink == true { continue }
            if v?.isDirectory == true && v?.isPackage != true {
                dirs.append(Entry(name: u.lastPathComponent, path: u.path, dir: true, dirs: hasInside(u, folders: false), bytes: 0))
            } else {
                files.append(Entry(name: u.lastPathComponent, path: u.path, dir: false, dirs: false, bytes: Int64(v?.fileSize ?? v?.totalFileAllocatedSize ?? 0)))
            }
            if dirs.count + files.count >= maxEntries { break }
        }
        let byName: (Entry, Entry) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return dirs.sorted(by: byName) + files.sorted(by: byName)
    }

    /// One folder found by Export's search: its name, its path, the folder Lumina has access to it was found under, how deep.
    struct Found: Equatable, Sendable {
        var name: String; var path: String; var root: String; var depth: Int
        var json: [String: Any] { ["name": name, "path": path, "root": root, "depth": depth] }
    }
    /// What a search found, how many folders it looked in, and whether it stopped early (time, folders looked in, or results).
    struct FindResult: Equatable, Sendable {
        var found: [Found]; var scanned: Int; var partial: Bool
    }

    /// The words of a search as they are compared: lowercased, accents off, split on spaces.
    static func words(_ q: String) -> [String] {
        q.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Folders whose name holds every word of `q`, under `roots` (each a folder Lumina has access to), breadth first so the
    /// shallow ones come first; hidden folders, packages and links are not entered. Stops after `limit` results, `maxScan`
    /// folders looked in, `budget` seconds or when `cancelled` says so, and says it stopped (`partial`). Ranked: a name that
    /// starts with the search first, then the shallower, then by name. Only names are read; nothing is opened.
    static func find(_ q: String, in roots: [URL], limit: Int = 200, maxScan: Int = 20_000, maxDepth: Int = 8, budget: TimeInterval = 2,
                     cancelled: () -> Bool = { false }) -> FindResult {
        let ws = words(q)
        guard !ws.isEmpty else { return FindResult(found: [], scanned: 0, partial: false) }
        let fm = FileManager.default, keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey], end = Date().addingTimeInterval(budget)
        var queue: [(URL, Int, String)] = [], seen = Set<String>(), found: [Found] = [], scanned = 0, partial = false, head = 0
        for r in roots { let p = r.standardizedFileURL.path; if seen.insert(p).inserted { queue.append((r.standardizedFileURL, 0, p)) } }
        while head < queue.count {
            if scanned >= maxScan || found.count >= limit || Date() > end || cancelled() { partial = true; break }
            let (dir, depth, root) = queue[head]; head += 1
            guard let names = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            scanned += 1
            for u in names {
                let v = try? u.resourceValues(forKeys: Set(keys))
                guard v?.isDirectory == true, v?.isPackage != true, v?.isSymbolicLink != true else { continue }
                let p = u.standardizedFileURL.path
                guard seen.insert(p).inserted else { continue }
                let name = u.lastPathComponent, folded = words(name).joined(separator: " ")
                if ws.allSatisfy({ folded.contains($0) }) {
                    found.append(Found(name: name, path: p, root: root, depth: depth + 1))
                    if found.count >= limit { break }
                }
                if depth + 1 < maxDepth { queue.append((u, depth + 1, root)) }
            }
        }
        if !partial && head < queue.count { partial = true }
        let first = ws[0]
        found.sort { a, b in
            let pa = words(a.name).first?.hasPrefix(first) ?? false, pb = words(b.name).first?.hasPrefix(first) ?? false
            if pa != pb { return pa }
            if a.depth != b.depth { return a.depth < b.depth }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return FindResult(found: found, scanned: scanned, partial: partial)
    }

    /// A new folder's name as typed: one plain name (no slash, no colon, no leading dot, no control characters), at
    /// most 120 characters; nil when nothing usable is left.
    static func folderName(_ typed: String) -> String? {
        var n = String(String.UnicodeScalarView(typed.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != "/" && $0 != ":" && $0 != "\\" }))
        n = n.trimmingCharacters(in: .whitespaces)
        while n.hasPrefix(".") { n.removeFirst() }
        n = String(n.prefix(120)).trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? nil : n
    }

    /// Makes `name` inside `parent`; a name already there is an answer, not a replacement.
    static func make(_ name: String, in parent: URL) -> (ok: Bool, path: String, why: String) {
        guard let clean = folderName(name) else { return (false, "", "That is not a folder name.") }
        let u = parent.appendingPathComponent(clean, isDirectory: true)
        if FileManager.default.fileExists(atPath: u.path) { return (false, u.path, "A folder named “\(clean)” is already there.") }
        do { try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false); return (true, u.path, "") }
        catch { return (false, "", "The folder could not be made there.") }
    }
}

/// The workshop's roots as read from disk (off the main thread): the folders Lumina has access to, by kind, and the drives
/// mounted, with their names, sizes and whether each is a card, read only, or one Lumina may look inside.
nonisolated struct SkimPlacesRead: Sendable {
    struct Place: Equatable, Sendable {
        var name: String; var path: String; var kind: String; var card: Bool
        var json: [String: Any] { ["name": name, "path": path, "kind": kind, "card": card] }
    }
    struct Drive: Equatable, Sendable {
        var name: String; var path: String; var card: Bool; var readOnly: Bool; var ejectable: Bool; var granted: Bool
        var total: Int64?; var free: Int64?
        var json: [String: Any] {
            var o: [String: Any] = ["name": name, "path": path, "card": card, "readOnly": readOnly, "ejectable": ejectable, "granted": granted]
            if let total { o["total"] = total }
            if let free { o["free"] = free }
            return o
        }
    }
    var places: [Place]
    var drives: [Drive]

    /// `kept` are the folders kept in `skim/places.json`, `roots` every folder Lumina may look inside.
    static func read(roots: [URL], shoot: URL?, save: URL?, kept: [URL]) -> SkimPlacesRead {
        var places: [Place] = [], seen = Set<String>()
        func add(_ u: URL, _ kind: String) {
            guard seen.insert(u.path).inserted else { return }
            places.append(Place(name: FileManager.default.displayName(atPath: u.path), path: u.path, kind: kind, card: SetsFileOps.isCard(u)))
        }
        if let shoot { add(shoot, "shoot") }
        if let save { add(save, "saveTo") }
        kept.forEach { add($0, "kept") }
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeIsReadOnlyKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsBrowsableKey]
        let drives = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []).compactMap { v -> Drive? in
            let r = try? v.resourceValues(forKeys: Set(keys))
            if r?.volumeIsBrowsable == false { return nil }
            // free space as Finder counts it (what macOS can free for an import included), else the plain figure
            let plain = r?.volumeAvailableCapacity.map(Int64.init), important = r?.volumeAvailableCapacityForImportantUsage
            let free = [plain, important].compactMap { $0 }.filter { $0 >= 0 }.max()
            return Drive(name: r?.volumeName ?? v.lastPathComponent, path: v.path, card: SetsFileOps.isCard(v), readOnly: r?.volumeIsReadOnly ?? false,
                         ejectable: (r?.volumeIsEjectable ?? false) || (r?.volumeIsRemovable ?? false), granted: roots.contains { SkimPlaces.inside(v.path, root: $0) },
                         total: r?.volumeTotalCapacity.map(Int64.init), free: free)
        }
        return SkimPlacesRead(places: places, drives: sorted(drives))
    }

    /// The Mac's own drive first, then the others by name.
    static func sorted(_ d: [Drive]) -> [Drive] {
        d.sorted { a, b in
            if (a.path == "/") != (b.path == "/") { return a.path == "/" }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

/// The newest search's number, shared with the search running off the main thread so it stops when a newer one starts.
nonisolated final class SkimFindGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var current: Int { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: Int) { lock.lock(); value = v; lock.unlock() }
}
