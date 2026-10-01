import Foundation

// WP-2. The folder to reopen after a relaunch (R-19): what was imported, where it is, and a
// bookmark for each place so it opens again without asking. It lives in the window's
// `PersistenceStore` as one snapshot under its own key, in the fields the contract has for it
// (`folderName`, `folderBookmark`, `folderPath`, `photoCount`); the full list of places rides in
// `tags`. Decisions and edits stay where they are, under the shoot's own key.

enum FolderMemory {
    /// The store key. Not a shoot: nothing else reads or writes it.
    static let key = "open.folder"

    struct Remembered: Equatable, Sendable {
        var name: String
        var count: Int
        /// `Shoot.key` of the local shoot, where its decisions are stored.
        var shootKey: String
        var roots: [FolderRoot]
    }

    /// Security-scoped when the system gives one (a sandboxed build needs it), plain otherwise.
    static func bookmark(_ url: URL) -> Data? {
        (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
    }

    /// Where a remembered place is now: through its bookmark (which follows a folder that was
    /// moved or renamed), then by its path. Nil when it is gone or can't be read without asking.
    static func resolve(_ root: FolderRoot) -> URL? {
        func readable(_ u: URL) -> Bool { FileManager.default.isReadableFile(atPath: u.path) }
        if let data = root.bookmark {
            for scoped in [true, false] {
                var stale = false
                let options: URL.BookmarkResolutionOptions = scoped ? [.withSecurityScope, .withoutUI] : [.withoutUI]
                guard let u = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
                // Held for the life of the process: the photos are read for as long as the shoot is open.
                if scoped { _ = u.startAccessingSecurityScopedResource() }
                if readable(u) { return u }
            }
        }
        let u = URL(fileURLWithPath: root.path)
        return readable(u) ? u : nil
    }

    static func save(_ r: Remembered, to store: any PersistenceStore, writer: String) {
        let first = r.roots.first { $0.isFolder } ?? r.roots.first
        var tags = ["shoot": r.shootKey]
        if let d = try? JSONEncoder().encode(r.roots), let s = String(data: d, encoding: .utf8) { tags["roots"] = s }
        // A full disk is WP-8's warning to give (it shows on the shoot's own write); not being able
        // to remember the folder only means it is asked for again.
        try? store.save(Snapshot(shootKey: key, tags: tags, folderName: r.name, folderBookmark: first?.bookmark, folderPath: first?.path,
                                 photoCount: r.count, writer: writer))
    }

    static func load(from store: any PersistenceStore) -> Remembered? {
        guard let s = try? store.load(shootKey: key), let name = s.folderName else { return nil }
        var roots = s.tags["roots"].flatMap { try? JSONDecoder().decode([FolderRoot].self, from: Data($0.utf8)) } ?? []
        if roots.isEmpty, let p = s.folderPath { roots = [FolderRoot(path: p, name: name, isFolder: true, bookmark: s.folderBookmark)] }
        return Remembered(name: name, count: s.photoCount, shootKey: s.tags["shoot"] ?? "", roots: roots)
    }

    static func forget(in store: any PersistenceStore) { try? store.clear(shootKey: key) }
}
