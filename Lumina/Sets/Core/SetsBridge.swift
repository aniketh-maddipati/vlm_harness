import AppKit
import WebKit

/// Where folders come from. The app asks the user (NSOpenPanel); the probe answers from a script.
@MainActor
protocol SetsChooser: AnyObject {
    /// The page asked to open a folder of ARWs (its `<input webkitdirectory>`).
    func chooseSource(allowsDirectories: Bool) async -> URL?
    /// Export needs a destination. `refusal` is set when the previous pick was refused.
    func chooseDestination(label: String, suggested: URL?, refusal: String?) async -> URL?
}

/// Native side of the page's plumbing (see Web/plumbing.js). Owns the folders the user opened,
/// the card watcher and every export.
@MainActor
final class SetsBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var webView: WKWebView?
    let chooser: SetsChooser
    let supportDir: URL
    let cards = SetsCardWatcher()
    /// Reads the opened folders for the page (listing, heads, previews). It also holds the opened
    /// folders by name: the page knows files as "<folder>/<file>".
    let ingest = SetsIngest()
    private var pendingSource: URL?
    private var lastOpened: URL?
    /// The folder macOS last refused to list (SAFETY.md 5): checkAccess and reopen use it.
    private var deniedFolder: URL?
    let shoots: SetsShootStore
    private(set) var ready = false
    var onEvent: ((String) -> Void)?
    /// The recent-shoots list changed (File ▸ Open Recent).
    var onShootsChanged: (() -> Void)?

    init(chooser: SetsChooser, supportDir: URL) {
        self.chooser = chooser
        self.supportDir = supportDir
        self.shoots = SetsShootStore(supportDir: supportDir)
        super.init()
        cards.onChange = { [weak self] card, removed in self?.cardChanged(card, removed: removed) }
        cards.onWillUnmount = { [weak self] volume in
            guard let self else { return }
            let stopped = self.ingest.markGone(volume: volume)
            if !stopped.isEmpty { self.onEvent?("eject: stopped reading \(stopped.joined(separator: ", "))") }
        }
    }

    func install(in conf: WKWebViewConfiguration) {
        conf.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "lumina")
    }

    // MARK: Opening folders

    /// Called from the web view's UI delegate for the page's folder input.
    func openPanel(allowsDirectories: Bool) async -> [URL]? {
        let url: URL?
        if let pending = pendingSource { url = pending; pendingSource = nil } else { url = await chooser.chooseSource(allowsDirectories: allowsDirectories) }
        guard let url else { return nil }
        ingest.register(url)
        lastOpened = url
        rememberBookmark(url)
        onEvent?("opened \(url.path)")
        return [url]
    }

    /// Opens a folder in the page as if the user picked it (menu, "Cull this card").
    func open(_ url: URL) {
        pendingSource = url
        webView?.evaluateJavaScript("window.__lumina && __lumina.openFolder()", completionHandler: nil)
    }

    func resolve(_ rel: String) -> URL? { ingest.resolve(rel) }      // no ../ escapes

    private func rememberBookmark(_ url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                ?? url.bookmarkData() else { return }
        let dir = supportDir.appendingPathComponent("bookmarks", isDirectory: true)
        try? SetsFileOps.replaceOwn(data, at: dir.appendingPathComponent(SetsFileOps.sha256(Data(url.path.utf8)).prefix(16) + ".bookmark"))
    }

    // MARK: Cards

    private func cardChanged(_ card: SetsCardWatcher.Card?, removed: SetsCardWatcher.Card?) {
        // Pulled: stop every read on it first, then tell the page what it has.
        let stopped = removed.map { ingest.markGone(volume: $0.volume) } ?? []
        if let card, !ingest.revive(volume: card.volume).isEmpty { onEvent?("card back: its folders read again") }
        let names = (try? JSONSerialization.data(withJSONObject: stopped)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        // Whether the open shoot lives on the volume that came or went (SAFETY.md 3).
        let ours = { (volume: URL) -> Bool in
            guard let open = self.lastOpened else { return false }
            let v = SetsIngest.plainPath(volume), o = SetsIngest.plainPath(open)
            return o == v || o.hasPrefix(v + "/")
        }
        var js: String
        if let card {
            js = "window.__lumina && __lumina.card(true, \(cardJSON(card)))"
            if ours(card.volume) { js += "; window.__lumina && __lumina.cardBack()" }
        } else {
            js = "window.__lumina && __lumina.cardGone(\(names), \(removed.map { ours($0.volume) } ?? false))"
        }
        if ready { webView?.evaluateJavaScript(js, completionHandler: nil) }
        onEvent?(card.map { "card in \($0.uuid)" } ?? "card out \(removed?.uuid ?? "?")" + (stopped.isEmpty ? "" : " · stopped reading \(stopped.joined(separator: ", "))"))
    }

    private func cardJSON(_ c: SetsCardWatcher.Card) -> String {
        let o: [String: Any] = ["name": c.name, "photos": c.arwCount, "bytes": c.bytes, "sony": c.sony, "uuid": c.uuid, "path": c.volume.path]
        return (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    // MARK: Page → native

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else { return (nil, "bad message") }
        switch op {
        case "ready":
            if let gaps = body["missing"] as? [String], !gaps.isEmpty {
                // A design sync removed or renamed something the plumbing needs.
                onEvent?("plumbing contract broken: \(gaps.joined(separator: ", "))")
                NSLog("Lumina plumbing contract broken: %@", gaps.joined(separator: ", "))
                return (false, nil)
            }
            ready = true
            webView?.evaluateJavaScript("window.__lumina && __lumina.card(\(cards.current != nil), \(cards.current.map(cardJSON) ?? "null"))", completionHandler: nil)
            onEvent?("ready")
            return (true, nil)
        case "cullCard":
            guard let card = cards.current, let dcim = card.folders.first?.deletingLastPathComponent() else { return (false, nil) }
            open(dcim)
            return (true, nil)
        case "openFolder":
            // Native ingest: pick (or take the pending folder), then list it before reading anything.
            guard let url = await openPanel(allowsDirectories: true)?.first else { return (NSNull(), nil) }
            if SetsIngest.accessDenied(url) {
                deniedFolder = url
                onEvent?("access denied \(url.path)")
                return (["denied": Self.volumeName(url)], nil)
            }
            deniedFolder = nil
            let t0 = Date()
            let listing = await Task.detached(priority: .userInitiated) { SetsIngest.list(url) }.value
            onEvent?("listed \(listing.files.count) ARW + \(listing.xmp.count) xmp + \(listing.others.count) other\(listing.onCard ? " (card)" : "") in \(Int(Date().timeIntervalSince(t0) * 1000)) ms · \(ingest.workers) readers")
            var d = listing.dictionary
            d["workers"] = ingest.workers
            return (d, nil)
        case "prefetch":
            let items = (body["items"] as? [[String: Any]] ?? []).compactMap { i -> SetsIngest.Preview? in
                guard let rel = i["p"] as? String else { return nil }
                return SetsIngest.Preview(rel: rel, offset: Int(i["o"] as? String ?? "") ?? i["o"] as? Int ?? 0,
                                          length: Int(i["l"] as? String ?? "") ?? i["l"] as? Int ?? 0,
                                          orientation: Int(i["ori"] as? String ?? "") ?? i["ori"] as? Int ?? 1)
            }
            ingest.prefetch(items)
            return (items.count, nil)
        case "ingestStats":
            return (ingest.snapshot.dictionary, nil)
        case "shootOpened":
            // The page finished reading a folder: remember it and hand back its saved session.
            guard let url = lastOpened ?? ingest.root(named: body["name"] as? String ?? "") else { return (nil, nil) }
            let id = SetsShootStore.id(for: url)
            let shoot = SetsShootStore.Shoot(id: id, title: url.lastPathComponent == "DCIM" ? (cards.current?.name ?? "Card") : url.lastPathComponent,
                                             path: url.path, volumeUUID: SetsFileOps.volumeID(url), photos: body["n"] as? Int ?? 0,
                                             firstCapture: body["date"] as? String ?? "", opened: Date(),
                                             bookmark: try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            try? shoots.upsert(shoot)
            onShootsChanged?()
            onEvent?("shoot \(id) \(url.path)")
            let session = shoots.session(id).flatMap { String(data: $0, encoding: .utf8) }
            return (["id": id, "session": session ?? NSNull()] as [String: Any], nil)
        case "saveSession":
            guard let id = body["id"] as? String, let json = body["json"] as? String else { return (false, nil) }
            do {
                try shoots.saveSession(id, Data(json.utf8))
                if let sum = body["summary"] as? [String: Any] {
                    try shoots.saveSummary(id, photos: sum["n"] as? Int, seen: sum["dec"] as? Int, keepers: sum["kp"] as? Int, last: sum["last"] as? String)
                }
                return (true, nil)
            } catch { return (false, "\(error)") }
        case "recents":
            return (shoots.index().map { recent($0) }, nil)
        case "reopen":
            return (reopen(id: body["id"] as? String ?? ""), nil)
        case "workingFiles":
            guard let id = body["id"] as? String else { return (0, nil) }
            return (shoots.bytes(id), nil)
        case "removeShoot":
            guard let id = body["id"] as? String else { return (false, nil) }
            try? shoots.remove(id)
            onShootsChanged?()
            return (true, nil)
        case "writeInto":
            return (await writeInto(label: body["label"] as? String ?? "", files: body["files"] as? [[String: Any]] ?? []), nil)
        case "writeSidecars":
            return (await writeSidecars(root: body["root"] as? String ?? "", files: body["files"] as? [[String: Any]] ?? []), nil)
        case "reveal":
            guard let url = revealURL(body["path"] as? String ?? "") else { return (false, nil) }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            onEvent?("reveal \(url.path)")
            return (true, nil)
        case "setPrefs":
            guard let prefs = body["prefs"] as? [String: Any] else { return (false, nil) }
            Self.savePrefs(prefs)
            return (true, nil)
        case "openSettings":
            // Privacy & Security → Files and Folders. Opening System Settings is the user's own click.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") { NSWorkspace.shared.open(url) }
            return (true, nil)
        case "checkAccess":
            return (deniedFolder.map { !SetsIngest.accessDenied($0) } ?? true, nil)
        case "reopenDenied":
            guard let url = deniedFolder else { return (false, nil) }
            deniedFolder = nil
            open(url)
            return (true, nil)
        case "reopenCurrent":
            // The card with the open shoot came back after a read it cut short: read it again.
            guard let url = lastOpened, FileManager.default.fileExists(atPath: url.path) else { return (false, nil) }
            open(url)
            return (true, nil)
        default:
            return (nil, "unknown op \(op)")
        }
    }

    /// Opens a recent shoot again (its security-scoped bookmark, else its path). False when the card
    /// is out or the folder moved.
    func reopen(id: String) -> Bool {
        guard let shoot = shoots.index().first(where: { $0.id == id }) else { return false }
        var stale = false
        let url = shoot.bookmark.flatMap { try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) }
            ?? URL(fileURLWithPath: shoot.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }      // card out / folder gone
        _ = url.startAccessingSecurityScopedResource()
        open(url)
        return true
    }

    /// A recent shoot in the page's own SHOOTS shape: d, n, dec, kp, last, where (+ id, which the
    /// plumbing's libOpen reopens natively).
    private func recent(_ s: SetsShootStore.Shoot) -> [String: Any] {
        let day = s.firstCapture.split(separator: " ").first.map { $0.replacingOccurrences(of: ":", with: "-") } ?? ""
        return ["id": s.id, "d": day.isEmpty ? s.title : day, "n": s.photos, "dec": s.seen ?? 0, "kp": s.keepers ?? 0, "last": s.last ?? "", "where": s.path]
    }

    /// Show in Finder: an absolute path, a page path ("<folder>/sub/DSC.ARW"), or an opened folder's name.
    private func revealURL(_ path: String) -> URL? {
        let url: URL?
        if path.hasPrefix("/") { url = URL(fileURLWithPath: path) }
        else if path.contains("/") { url = resolve(path) }
        else { url = ingest.root(named: path) ?? lastOpened }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return lastOpened }
        return url
    }

    /// The volume's name for the access banner: "SONY-A7M4", or the folder's name on the startup disk.
    static func volumeName(_ url: URL) -> String {
        let v = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeIsRootFileSystemKey])
        if v?.volumeIsRootFileSystem == true { return url.lastPathComponent }
        return v?.volumeName ?? url.lastPathComponent
    }

    // MARK: Settings (MENUS.md): stored per user

    static let prefsKey = "lumina-prefs"

    static var prefs: [String: Any]? {
        guard let text = UserDefaults.standard.string(forKey: prefsKey), let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func savePrefs(_ prefs: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: prefs, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(text, forKey: prefsKey)
    }

    // MARK: Save (SAFETY.md 1)

    /// Save writes one .xmp sidecar per keeper INTO the shoot folder (`root`, an opened folder's
    /// name), next to its RAW. Every file goes through SetsFileOps.writeSidecar; nothing is retried
    /// silently. Refused wholesale when the folder is on a card.
    private func writeSidecars(root name: String, files: [[String: Any]]) async -> [String: Any]? {
        guard let root = ingest.root(named: name) ?? lastOpened.flatMap({ $0.lastPathComponent == name ? $0 : nil }) else {
            onEvent?("writeSidecars: \(name) is not an opened folder")
            return nil
        }
        onEvent?("writeSidecars \(files.count) → \(root.path)")
        let items: [(String, Data?)] = files.map { ($0["name"] as? String ?? "", ($0["b64"] as? String).flatMap { Data(base64Encoded: $0) }) }
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Lumina save")
        let (n, bak, errors) = await Task.detached(priority: .userInitiated) { () -> (Int, Int, [[String: String]]) in
            var n = 0, bak = 0, errors: [[String: String]] = []
            let onCard = SetsFileOps.isCard(root)
            for (rel, data) in items {
                let stem = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
                guard let data else { errors.append(["name": stem, "reason": "failed"]); continue }
                if onCard { errors.append(["name": stem, "reason": "on the card"]); continue }
                do {
                    if try SetsFileOps.writeSidecar(data, rel: rel, root: root).backedUp { bak += 1 }
                    n += 1
                } catch let e as SetsFileOps.SidecarError {
                    errors.append(["name": e.name, "reason": e.reason])
                } catch {
                    errors.append(["name": stem, "reason": SetsFileOps.reason(error)])
                }
            }
            return (n, bak, errors)
        }.value
        ProcessInfo.processInfo.endActivity(activity)
        onEvent?("sidecars → \(root.path): \(n) written, \(bak) bak, \(errors.count) failed\(errors.first.map { " — \($0["name"] ?? "") · \($0["reason"] ?? "")" } ?? "")")
        return ["n": n, "bak": bak, "folder": root.lastPathComponent, "path": root.path, "errors": errors]
    }

    private func writeInto(label: String, files: [[String: Any]]) async -> [String: Any] {
        onEvent?("writeInto \(label): \(files.count) files")
        var items: [SetsExportJob.Item] = []
        var sources: [URL] = ingest.rootURLs
        for f in files {
            guard let name = f["name"] as? String, !name.contains(".."), !name.hasPrefix("/") else { return ["aborted": true, "say": "export stopped · bad file name"] }
            if let b = f["b64"] as? String, let data = Data(base64Encoded: b) {
                items.append(.bytes(name: name, data: data))
            } else if let rel = f["src"] as? String {
                guard let src = resolve(rel) else { return ["aborted": true, "say": "export stopped · can't find \(rel)"] }
                items.append(.copy(name: name, source: src)); sources.append(src.deletingLastPathComponent())
            } else if let j = f["jpg"] as? [String: Any], let rel = j["src"] as? String {
                guard let src = resolve(rel) else { return ["aborted": true, "say": "export stopped · can't find \(rel)"] }
                items.append(.jpeg(name: name, source: src, css: j["css"] as? String ?? "none", px: j["px"] as? String ?? "full"))
            }
        }
        // Pick the destination; refuse the card and the source folder, and ask again.
        var refusal: String?
        var dest: URL?
        while dest == nil {
            guard let picked = await chooser.chooseDestination(label: label, suggested: ingest.rootURLs.first?.deletingLastPathComponent(), refusal: refusal) else {
                return ["aborted": true]
            }
            if let why = SetsFileOps.refusal(destination: picked, sources: sources) { refusal = why; onEvent?("refused \(picked.path)"); continue }
            dest = picked
        }
        let job = SetsExportJob(label: label, destination: dest!, items: items)
        let journal = SetsExportJournal(directory: supportDir.appendingPathComponent("exports", isDirectory: true))
        // Keep the export at full speed when Lumina is in the background (App Nap) and the Mac awake.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Lumina export")
        let result = await Task.detached(priority: .userInitiated) { [sources] in job.run(journal: journal, sources: sources) }.value
        ProcessInfo.processInfo.endActivity(activity)
        onEvent?("export \(label) → \(dest!.path): \(result.n) written, \(result.bak) bak, \(result.failed.count) failed\(result.failed.first.map { " — " + $0 } ?? "")")
        if let first = result.failed.first {
            return ["aborted": true, "say": result.n > 0 ? "export stopped after \(result.n) · \(first)" : first]
        }
        return ["n": result.n, "bak": result.bak, "folder": result.folder]
    }
}

/// The page's web view: bundled files only, network blocked, plumbing injected.
@MainActor
enum SetsWebView {
    static func make(pageRoot: URL, vendorRoot: URL, plumbing: String, bridge: SetsBridge?, standInPhotos: Bool,
                     config: [String: Any] = [:], extraScripts: [String] = [], frame: CGRect = .zero) async throws -> (WKWebView, SetsSchemeHandler) {
        let conf = WKWebViewConfiguration()
        conf.websiteDataStore = .nonPersistent()
        let scheme = SetsSchemeHandler(pageRoot: pageRoot, vendorRoot: vendorRoot, standInPhotos: standInPhotos, ingest: bridge?.ingest)
        conf.setURLSchemeHandler(scheme, forURLScheme: SetsSchemeHandler.scheme)
        let ucc = conf.userContentController
        let res = String(data: try JSONSerialization.data(withJSONObject: SetsSchemeHandler.resources), encoding: .utf8)!
        ucc.addUserScript(WKUserScript(source: "window.__resources=Object.assign(window.__resources||{},\(res));", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        for s in extraScripts { ucc.addUserScript(WKUserScript(source: s, injectionTime: .atDocumentStart, forMainFrameOnly: true)) }
        let cfg = String(data: try JSONSerialization.data(withJSONObject: config), encoding: .utf8)!
        ucc.addUserScript(WKUserScript(source: "window.__luminaConfig=\(cfg);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if bridge != nil { ucc.addUserScript(WKUserScript(source: plumbing, injectionTime: .atDocumentStart, forMainFrameOnly: true)) }
        bridge?.install(in: conf)
        let rules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
        if let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "lumina-offline", encodedContentRuleList: rules) {
            ucc.add(list)
        }
        let wv = WKWebView(frame: frame, configuration: conf)
        bridge?.webView = wv
        return (wv, scheme)
    }
}
