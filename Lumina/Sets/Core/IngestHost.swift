import AppKit
import WebKit

/// The native side of Lumina Ingest (Debug, `LUMINA_PAGE=ingest`): the folders chosen in its open panel, the
/// library folder (picked once, a security-scoped bookmark), the background copy and Eject. Its ops answer the
/// ingest page only (`SetsBridge`); docs/release/TRUST.md lists them.
@MainActor
final class IngestHost {
    static let ops: Set<String> = ["ingestLibrary", "ingestPickLibrary", "ingestHas", "ingestForget", "ingestCopy", "ingestEject"]

    weak var webView: WKWebView?
    let store: IngestLibrary
    var onEvent: ((String) -> Void)?
    /// Swapped out by tests.
    var choose: (String?) async -> URL? = IngestHost.panel
    var eject: (URL) throws -> Void = { try NSWorkspace.shared.unmountAndEjectDevice(at: $0) }

    /// What the owner chose in Ingest's open panel this run (a card's root, folders, files), held for the copy.
    private(set) var roots: [URL] = []
    private var libraryURL: URL?
    /// One file the page sent: every chosen file its path can name (`resolveAll`); the copy takes the one whose bytes
    /// are the page's key.
    private struct Job: Sendable { var key: String; var cands: [URL]; var root: URL; var roots: [URL]; var folder: String; var src: String }
    private var queue: [Job] = []
    private var running = false
    /// Per source label the page uses: how many were sent, verified, failed; its root and whether it is a whole card
    /// (a card's root: only then can "safe to format" be said; one folder of a card leaves the rest uncopied).
    private struct Tally { var sent = 0, ok = 0, bad = 0; var root: URL?; var card = false }
    private var tally: [String: Tally] = [:]
    /// Source files with a verified copy this run (standardized paths): what a card is checked against.
    private var verified: Set<String> = []

    init(supportDir: URL) {
        store = IngestLibrary(url: supportDir.appendingPathComponent("ingest", isDirectory: true).appendingPathComponent("library.json"))
        if let data = store.bookmark {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale), u.startAccessingSecurityScopedResource() {
                libraryURL = u
            }
        }
    }

    func picked(_ urls: [URL]) { roots.append(contentsOf: urls) }

    /// Open in Pick from the library: "<library>/<rel>" for every key, when each has a checked copy still there; nil
    /// when any is missing (Pick then opens the sources).
    func libraryPaths(keys: [String]) -> (paths: [String], root: URL)? {
        guard !keys.isEmpty, let lib = libraryURL?.standardizedFileURL else { return nil }
        var paths: [String] = []
        for k in keys {
            guard let e = store.entry(k), FileManager.default.fileExists(atPath: lib.appendingPathComponent(e.rel).path) else { return nil }
            paths.append(lib.lastPathComponent + "/" + e.rel)
        }
        return (paths, lib)
    }

    private func libraryJSON() -> [String: Any] {
        ["folder": libraryURL.map { $0.lastPathComponent } ?? NSNull(), "count": store.count, "keys": store.keys]
    }

    func handle(_ op: String, _ body: [String: Any]) async -> Any? {
        switch op {
        case "ingestLibrary":
            return libraryJSON()
        case "ingestHas":
            return store.has((body["keys"] as? [String] ?? []).prefix(100_000).map { $0 })
        case "ingestForget":
            store.forget(); Self.save(store)
            return libraryJSON()
        case "ingestPickLibrary":
            return await pickLibrary(refusal: nil)
        case "ingestCopy":
            if libraryURL == nil, (await pickLibrary(refusal: nil))["folder"] is NSNull { return ["error": "no library"] }
            guard let lib = libraryURL else { return ["error": "no library"] }
            var n = 0, unresolved: [[String: Any]] = []
            for d in (body["items"] as? [[String: Any]] ?? []).prefix(200_000) {
                let key = d["key"] as? String ?? "", path = d["path"] as? String ?? "", src = d["src"] as? String ?? ""
                var t = tally[src] ?? Tally(); t.sent += 1
                let found = IngestCopy.resolveAll(path, roots: roots)
                guard let (_, root) = found.first else {
                    t.bad += 1; tally[src] = t
                    unresolved.append(["key": key, "src": src, "ok": false, "why": "not found on disk"]); continue
                }
                if t.root == nil { t.root = root; t.card = SetsFileOps.isCard(root) && IngestCopy.isVolumeRoot(root) }
                tally[src] = t
                queue.append(Job(key: key, cands: found.map(\.file), root: root, roots: found.map(\.root), folder: d["folder"] as? String ?? "No date", src: src))
                n += 1
            }
            for u in unresolved { post(u, src: u["src"] as? String ?? "") }
            pump()
            return ["queued": n, "unresolved": unresolved.count, "folder": lib.lastPathComponent]
        case "ingestEject":
            let src = body["src"] as? String ?? ""
            guard let t = tally[src], let root = t.root else { return ["ok": false, "why": "nothing copied from it"] }
            guard t.card else { return ["ok": false, "why": "not a whole card"] }
            guard let vol = (try? root.resourceValues(forKeys: [.volumeURLKey]))?.volume else { return ["ok": false, "why": "no volume"] }
            // Every source on that volume: all sent, all verified, none failed, none waiting.
            for (_, o) in tally where o.root.flatMap({ (try? $0.resourceValues(forKeys: [.volumeURLKey]))?.volume?.path }) == vol.path {
                if o.bad > 0 || o.ok < o.sent { return ["ok": false, "why": "not every file copied"] }
            }
            if running || queue.contains(where: { $0.root.path.hasPrefix(vol.path) }) { return ["ok": false, "why": "still copying"] }
            // And the card itself: every file on it has a verified copy, not only the ones the page sent.
            let left = await audit(vol)
            if !left.isEmpty { return ["ok": false, "why": "\(left.count) \(left.count == 1 ? "file" : "files") on the card not copied"] }
            do { try eject(vol); onEvent?("ingest: ejected \(src)"); return ["ok": true] }
            catch { return ["ok": false, "why": (error as NSError).localizedDescription] }
        default:
            return nil
        }
    }

    private func pickLibrary(refusal: String?) async -> [String: Any] {
        guard let u = await choose(refusal) else { return libraryJSON() }
        if let why = SetsFileOps.refusal(destination: u, sources: roots) {
            return await pickLibrary(refusal: why)
        }
        libraryURL?.stopAccessingSecurityScopedResource()
        libraryURL = u
        _ = u.startAccessingSecurityScopedResource()
        store.setFolder(u.standardizedFileURL.path, bookmark: try? u.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
        Self.save(store)
        return libraryJSON()
    }

    private static func panel(_ refusal: String?) async -> URL? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.allowsMultipleSelection = false
        p.prompt = "Choose"
        p.message = refusal ?? "Choose the library folder. Lumina copies into it and checks every copy."
        return await p.begin() == .OK ? p.url : nil
    }

    private func pump() {
        guard !running, !queue.isEmpty, let lib = libraryURL else { return }
        running = true
        let jobs = queue; queue = []
        let store = self.store
        Task.detached(priority: .utility) { [weak self] in
            var n = 0
            for j in jobs {
                // Two chosen folders of one name: the file whose bytes are the page's key (else the first, which the
                // copy then refuses as "not the file that was read").
                let i = j.cands.count > 1 && !j.key.isEmpty ? (j.cands.firstIndex { IngestCopy.pageKey($0) == j.key } ?? 0) : 0
                let r = IngestCopy.copy(IngestCopy.Item(key: j.key, source: j.cands[i], root: j.roots[i], folder: j.folder), into: lib, store: store)
                n += 1
                if n % 20 == 0 { Self.save(store) }
                await self?.finished(r, src: j.src)
            }
            Self.save(store)
            await self?.drained()
        }
    }

    private func finished(_ r: IngestCopy.Result, src: String) {
        var t = tally[src] ?? Tally()
        if r.ok { t.ok += 1; verified.formUnion(r.sources) } else { t.bad += 1 }
        tally[src] = t
        var d: [String: Any] = ["key": r.key, "src": src, "ok": r.ok, "files": r.files, "bytes": r.bytes, "already": r.already, "card": t.card]
        if let w = r.why { d["why"] = w }
        post(d, src: src)
    }

    private func drained() {
        running = false
        pump()
        guard !running else { return }
        // A whole card whose sent files are all done: count what is still only on it, for "safe to format".
        var vols: [String: URL] = [:]
        for (_, t) in tally where t.card && t.ok + t.bad == t.sent {
            if let r = t.root, let v = (try? r.resourceValues(forKeys: [.volumeURLKey]))?.volume { vols[v.path] = v }
        }
        for (_, v) in vols {
            Task { [weak self] in
                guard let self else { return }
                let left = await self.audit(v)
                for (src, t) in self.tally where t.card && t.root.flatMap({ (try? $0.resourceValues(forKeys: [.volumeURLKey]))?.volume?.path }) == v.path {
                    var d: [String: Any] = ["src": src, "left": left.count]
                    if let f = left.first { d["first"] = f }
                    self.webView?.evaluateJavaScript("window.luminaIngest && luminaIngest.audited && luminaIngest.audited(\(SetsBridge.json(d)))", completionHandler: nil)
                }
            }
        }
    }

    /// The files on the card at `volume` without a verified copy (`IngestCopy.unaccounted`), off the main thread.
    private func audit(_ volume: URL) async -> [String] {
        let copied = verified
        let left = await Task.detached(priority: .utility) { IngestCopy.unaccounted(under: volume, copied: copied) }.value
        if !left.isEmpty { LuminaLog.app.info("ingest: \(left.count, privacy: .public) files on a card without a copy") }
        return left
    }

    /// The library's record; a failed write costs only re-checking next time, but is logged, never dropped.
    nonisolated static func save(_ store: IngestLibrary) {
        do { try store.save() } catch { LuminaLog.app.error("ingest: library record not saved: \(String(describing: error), privacy: .private)") }
    }

    private func post(_ d: [String: Any], src: String) {
        webView?.evaluateJavaScript("window.luminaIngest && luminaIngest.copied(\(SetsBridge.json(d)))", completionHandler: nil)
    }
}
