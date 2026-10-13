import Foundation

/// What a shoot is made of besides the folder it was opened from (BRIDGE.md "Sources"): folders
/// and single files added later (the panel, a drop, AirDrop arrivals), and, for a shoot that was
/// opened from single files, those files. One file per shoot, beside the shoot store:
///   sources/<shoot id>.json
/// It holds no photo and no decision: names, and the security-scoped bookmarks (`SetsSources`)
/// that are the only way back to each source after a relaunch. Lumina's own file; removing a
/// shoot's working files leaves it (a shoot without it still opens, from its first folder only).
nonisolated struct SetsShootSources {
    struct Entry: Codable, Equatable {
        /// Stable for the life of the shoot; the page's plumbing names a source by it.
        var nid: String
        /// The first segment of its photos' paths ("<name>/DSC00001.ARW"): the folder's name, or
        /// another one when the shoot already holds a root called that ("100MSDCF 2").
        var name: String
        var kind: String
        var label: String
        /// The source is these files of one folder, not the folder (nil: the whole folder).
        var files: [String]?
        /// `SetsSources` ids: one for a folder, one per file (same order as `files`).
        var refs: [String]
        /// The shoot was opened from these files: its first source, not an added one.
        var primary: Bool?
        /// The page's clock shift for this source's photos, in seconds (nil: none).
        var offset: Int?
        /// Photos it had when last read, for a source that is not connected.
        var n: Int?

        var isPrimary: Bool { primary == true }
    }

    struct Stored: Codable {
        var entries: [Entry] = []
        var grants = SetsSources()
    }

    static let maxEntries = 64
    static let maxFiles = 2000

    let root: URL

    init(supportDir: URL) { root = supportDir.appendingPathComponent("sources", isDirectory: true) }

    private func file(_ id: String) -> URL? {
        SetsShootStore.isID(id) ? root.appendingPathComponent(id + ".json") : nil
    }

    func load(_ id: String) -> Stored {
        guard let url = file(id), let data = try? Data(contentsOf: url), data.count <= 8 << 20 else { return Stored() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(Stored.self, from: data)) ?? Stored()
    }

    func save(_ id: String, _ stored: Stored) throws {
        guard let url = file(id) else { throw SetsFileOps.Failure("not a shoot id") }
        if stored.entries.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try SetsFileOps.replaceOwn(try enc.encode(stored), at: url)
    }

    func remove(_ id: String) {
        if let url = file(id) { try? FileManager.default.removeItem(at: url) }
    }

    static func newID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))
    }

    // MARK: Names

    /// A root name no other root of the shoot has: `base`, else "base 2", "base 3"…
    static func alias(_ base: String, taken: Set<String>) -> String {
        let base = base.isEmpty || base.contains("/") ? "Folder" : base
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// The place (`SetsShootStore.id(for:)` form) of a shoot opened from single files: their
    /// folder's place and their names, so two picks from one Downloads folder are two shoots.
    static func loosePlace(folder: String, names: Set<String>) -> String {
        String(SetsFileOps.sha256(Data((folder + "|" + names.sorted().joined(separator: "/")).utf8)).prefix(16))
    }

    // MARK: What the page was handed, matched to what the user granted

    struct Claim: Equatable {
        /// The folder, or the folder the files are in.
        var url: URL
        /// The files (nil: the whole folder).
        var only: Set<String>?
        /// The root's name before it is made unique in the shoot.
        var base: String
    }

    /// The page got `File`s from a drop or its file input and names them by relative path. The
    /// Mac was handed the same items as URLs (`granted`, newest last). A path whose first segment
    /// is a granted folder's name is that folder, whole; any other file is matched by its own name
    /// to a granted file, and files of one folder make one root limited to them. Files that match
    /// nothing are left out: nothing is ever read that was not granted.
    static func claims(files: [String], granted: [(url: URL, isDirectory: Bool)]) -> [Claim] {
        var out: [Claim] = []
        var folders: [String: URL] = [:], singles: [String: URL] = [:]
        for g in granted {                                   // newest wins
            if g.isDirectory { folders[g.url.lastPathComponent] = g.url } else { singles[g.url.lastPathComponent] = g.url }
        }
        var taken = Set<String>()
        var loose: [String: (url: URL, names: Set<String>, base: String)] = [:], order: [String] = []
        for rel in files {
            let parts = rel.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard let name = parts.last, parts.count <= 64 else { continue }
            if parts.count > 1, let folder = folders[parts[0]] {
                if taken.insert(parts[0]).inserted { out.append(Claim(url: folder, only: nil, base: parts[0])) }
                continue
            }
            guard parts.count <= 2, SetsIngest.isPlainName(name), let file = singles[name] else { continue }
            let parent = file.deletingLastPathComponent()
            let base = parts.count == 2 ? parts[0] : parent.lastPathComponent
            let key = parent.standardizedFileURL.path + "|" + base
            if loose[key] == nil { loose[key] = (parent, [], base); order.append(key) }
            loose[key]?.names.insert(name)
        }
        for key in order { if let l = loose[key] { out.append(Claim(url: l.url, only: l.names, base: l.base)) } }
        return out
    }
}
