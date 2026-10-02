import Foundation

/// The one owner of security-scoped access (threat model T9, release task R1b). In the App
/// Sandbox a folder the user picked in a panel is readable until the app quits; after a relaunch
/// the only way back in is the bookmark kept in the shoot index, and resolving it gives a URL whose
/// access must be started, and stopped again, by the app. macOS limits how many a process may
/// hold, so this is the only place that calls start and stop:
///
/// - the open shoot holds its folder; opening another, or closing it, lets it go;
/// - an in-flight Save or export can `hold` a folder too, so a shoot closed under it keeps its
///   access until the work is done (`release`);
/// - a folder is started once however many users it has, and stopped when the last one goes,
///   only if this owner started it (a panel's grant is the system's and is never stopped here).
///
/// Start, stop, bookmark resolution and creation are injected, so the bookkeeping is tested
/// without a sandbox (`SetsAccessTests`).
@MainActor
final class SetsAccess {
    struct Calls {
        var start: (URL) -> Bool
        var stop: (URL) -> Void
        /// The bookmark's folder now, and whether the bookmark is stale. Throws when it cannot be
        /// resolved (folder gone, volume not mounted, a refusal).
        var resolve: (Data) throws -> (url: URL, stale: Bool)
        /// A security-scoped bookmark for a folder this process can reach now.
        var bookmark: (URL) throws -> Data
        var exists: (URL) -> Bool

        static let system = Calls(
            start: { $0.startAccessingSecurityScopedResource() },
            stop: { $0.stopAccessingSecurityScopedResource() },
            resolve: { data in
                var stale = false
                // Never a dialog and never a mount: a recent on a server or a card that is out is
                // simply not available.
                let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale)
                return (url, stale)
            },
            bookmark: { try $0.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) },
            exists: { url in
                var dir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
            })
    }

    private struct Entry { let url: URL; var users: Int; let started: Bool }

    private let calls: Calls
    private var entries: [String: Entry] = [:]
    private var shootKey: String?
    private var holds: [Int: String] = [:]
    private var nextHold = 1
    /// For tests and the log: how often start and stop were called.
    private(set) var starts = 0, stops = 0
    var onLog: ((String) -> Void)?

    init(calls: Calls = .system) { self.calls = calls }

    private static func key(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    /// Folders whose access this owner started and has not stopped.
    var started: Int { entries.values.filter(\.started).count }
    /// The open shoot's folder, if any.
    var shoot: URL? { shootKey.flatMap { entries[$0]?.url } }

    private func acquire(_ url: URL, scoped: Bool) -> String {
        let k = Self.key(url)
        if var e = entries[k] { e.users += 1; entries[k] = e; return k }
        let on = scoped && calls.start(url)
        if on { starts += 1; onLog?("started \(url.lastPathComponent) (\(started + 1) held)") }
        entries[k] = Entry(url: url, users: 1, started: on)
        return k
    }

    private func release(key k: String) {
        guard var e = entries[k] else { return }
        e.users -= 1
        if e.users > 0 { entries[k] = e; return }
        entries[k] = nil
        if e.started { calls.stop(e.url); stops += 1; onLog?("stopped \(e.url.lastPathComponent) (\(started) held)") }
    }

    /// `url` is now the open shoot. `scoped`: its access has to be started (a URL from a resolved
    /// bookmark); false for a folder the process can already reach (a panel's pick). The shoot
    /// open before it is let go after, so reopening the same folder never stops and restarts it.
    func openShoot(_ url: URL, scoped: Bool) {
        let k = acquire(url, scoped: scoped)
        if let old = shootKey { release(key: old) }
        shootKey = k
    }

    /// No shoot is open (File ▸ Close, or the page started over).
    func closeShoot() {
        if let old = shootKey { release(key: old) }
        shootKey = nil
    }

    /// Keeps `url` reachable for a piece of work (Save, export) even if the shoot is closed or
    /// another opened meanwhile. Pass the token to `release`.
    func hold(_ url: URL, scoped: Bool = true) -> Int {
        let t = nextHold; nextHold += 1
        holds[t] = acquire(url, scoped: scoped)
        return t
    }

    func release(_ token: Int) {
        guard let k = holds.removeValue(forKey: token) else { return }
        release(key: k)
    }

    /// Opens a recent shoot through its bookmark: resolved, its access started, and checked. A
    /// stale bookmark is made again from the resolved folder and saved with where the folder is
    /// now. Nil when there is no bookmark, it cannot be resolved, or the folder is not there:
    /// the caller tells the user it is not available. There is no fallback to the stored path,
    /// which a sandbox refuses anyway; the path is for display only.
    func reopen(_ shoot: SetsShootStore.Shoot, store: SetsShootStore, place: (URL) -> String = SetsShootStore.id(for:)) -> URL? {
        guard let data = shoot.bookmark else { onLog?("reopen \(shoot.id): no bookmark"); return nil }
        let resolved: (url: URL, stale: Bool)
        do { resolved = try calls.resolve(data) } catch { onLog?("reopen \(shoot.id): bookmark not resolved (\(error.localizedDescription))"); return nil }
        let k = acquire(resolved.url, scoped: true)
        guard calls.exists(resolved.url) else {
            release(key: k)
            onLog?("reopen \(shoot.id): folder not there")
            return nil
        }
        if resolved.stale {
            do {
                try store.renewBookmark(shoot.id, try calls.bookmark(resolved.url), path: resolved.url.path, place: place(resolved.url))
                onLog?("reopen \(shoot.id): stale bookmark renewed")
            } catch { onLog?("reopen \(shoot.id): stale bookmark not renewed (\(error.localizedDescription))") }
        }
        if let old = shootKey { release(key: old) }
        shootKey = k
        return resolved.url
    }

    /// A folder opened from a panel that is a recent shoot renamed or moved since (its stored path
    /// is gone and its bookmark now resolves here): that shoot, so its decisions come with it.
    /// Only recents on the same volume are resolved; nothing is started.
    func movedShoot(to url: URL, volume: String?, in store: SetsShootStore) -> SetsShootStore.Shoot? {
        let here = Self.key(url)
        for s in store.index() where s.volumeUUID == volume && Self.key(URL(fileURLWithPath: s.path)) != here {
            guard let data = s.bookmark, !calls.exists(URL(fileURLWithPath: s.path)),
                  let r = try? calls.resolve(data), Self.key(r.url) == here else { continue }
            return s
        }
        return nil
    }

    /// Bookmarks written by earlier builds one per open to `bookmarks/`, never read: removed once.
    nonisolated static func removeLegacyBookmarks(supportDir: URL) {
        let dir = supportDir.appendingPathComponent("bookmarks", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
