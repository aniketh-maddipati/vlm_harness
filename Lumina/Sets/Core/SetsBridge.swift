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
    /// Opened folders by name — the page knows files by `webkitRelativePath` ("<folder>/<file>").
    private(set) var roots: [String: URL] = [:]
    private var pendingSource: URL?
    private(set) var ready = false
    var onEvent: ((String) -> Void)?

    init(chooser: SetsChooser, supportDir: URL) {
        self.chooser = chooser
        self.supportDir = supportDir
        super.init()
        cards.onChange = { [weak self] card, removed in self?.cardChanged(card, removed: removed) }
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
        roots[url.lastPathComponent] = url
        rememberBookmark(url)
        onEvent?("opened \(url.path)")
        return [url]
    }

    /// Opens a folder in the page as if the user picked it (menu, "Cull this card").
    func open(_ url: URL) {
        pendingSource = url
        webView?.evaluateJavaScript("window.__lumina && __lumina.openFolder()", completionHandler: nil)
    }

    func resolve(_ rel: String) -> URL? {
        let parts = rel.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let root = roots[parts[0]] else { return nil }
        let url = root.appendingPathComponent(parts[1]).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else { return nil }      // no ../ escapes
        return url
    }

    private func rememberBookmark(_ url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                ?? url.bookmarkData() else { return }
        let dir = supportDir.appendingPathComponent("bookmarks", isDirectory: true)
        try? SetsFileOps.replaceOwn(data, at: dir.appendingPathComponent(SetsFileOps.sha256(Data(url.path.utf8)).prefix(16) + ".bookmark"))
    }

    // MARK: Cards

    private func cardChanged(_ card: SetsCardWatcher.Card?, removed: SetsCardWatcher.Card?) {
        let js = card != nil ? "window.__lumina && __lumina.card(true)" : "window.__lumina && (__lumina.card(false), __lumina.say('Card removed · re-insert to keep going'))"
        if ready { webView?.evaluateJavaScript(js, completionHandler: nil) }
        onEvent?(card.map { "card in \($0.uuid)" } ?? "card out \(removed?.uuid ?? "?")")
    }

    // MARK: Page → native

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else { return (nil, "bad message") }
        switch op {
        case "ready":
            ready = true
            webView?.evaluateJavaScript("window.__lumina && __lumina.card(\(cards.current != nil))", completionHandler: nil)
            onEvent?("ready")
            return (true, nil)
        case "cullCard":
            guard let card = cards.current, let dcim = card.folders.first?.deletingLastPathComponent() else { return (false, nil) }
            open(dcim)
            return (true, nil)
        case "writeInto":
            return (await writeInto(label: body["label"] as? String ?? "", files: body["files"] as? [[String: Any]] ?? []), nil)
        default:
            return (nil, "unknown op \(op)")
        }
    }

    private func writeInto(label: String, files: [[String: Any]]) async -> [String: Any] {
        var items: [SetsExportJob.Item] = []
        var sources: [URL] = Array(roots.values)
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
            guard let picked = await chooser.chooseDestination(label: label, suggested: roots.values.first?.deletingLastPathComponent(), refusal: refusal) else {
                return ["aborted": true]
            }
            if let why = SetsFileOps.refusal(destination: picked, sources: sources) { refusal = why; onEvent?("refused \(picked.path)"); continue }
            dest = picked
        }
        let job = SetsExportJob(label: label, destination: dest!, items: items)
        let journal = SetsExportJournal(directory: supportDir.appendingPathComponent("exports", isDirectory: true))
        // Keep the export at full speed when Lumina is in the background (App Nap) and the Mac awake.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Lumina export")
        let result = await Task.detached(priority: .userInitiated) { job.run(journal: journal) }.value
        ProcessInfo.processInfo.endActivity(activity)
        onEvent?("export \(label) → \(dest!.path): \(result.n) written, \(result.bak) bak, \(result.failed.count) failed")
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
                     extraScripts: [String] = [], frame: CGRect = .zero) async throws -> (WKWebView, SetsSchemeHandler) {
        let conf = WKWebViewConfiguration()
        conf.websiteDataStore = .nonPersistent()
        let scheme = SetsSchemeHandler(pageRoot: pageRoot, vendorRoot: vendorRoot, standInPhotos: standInPhotos)
        conf.setURLSchemeHandler(scheme, forURLScheme: SetsSchemeHandler.scheme)
        let ucc = conf.userContentController
        let res = String(data: try JSONSerialization.data(withJSONObject: SetsSchemeHandler.resources), encoding: .utf8)!
        ucc.addUserScript(WKUserScript(source: "window.__resources=Object.assign(window.__resources||{},\(res));", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        for s in extraScripts { ucc.addUserScript(WKUserScript(source: s, injectionTime: .atDocumentStart, forMainFrameOnly: true)) }
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
