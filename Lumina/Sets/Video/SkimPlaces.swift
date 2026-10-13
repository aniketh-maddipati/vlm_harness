import Foundation

/// Export's workshop (the folder tree): the drives mounted on this Mac, the folders the user has let Skim into, and the
/// folders inside those. macOS lets a sandboxed app name a drive but not look inside it until the user picks it (or a
/// folder on it) in the folder panel once; each folder picked is kept as a security-scoped bookmark in
/// `skim/places.json`. Listing shows folders only (no files, nothing hidden) and never leaves a granted folder; a new
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
            let kids = (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            let dirs = kids.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            out.append(Folder(name: u.lastPathComponent, path: u.path, dirs: dirs))
            if out.count >= maxListed { break }
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
