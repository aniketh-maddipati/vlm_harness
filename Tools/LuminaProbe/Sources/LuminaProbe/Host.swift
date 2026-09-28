import AppKit
import WebKit

/// One offscreen window holding one WKWebView — the same engine and the same key/mouse path
/// (NSEvent → first responder) the app uses. Collects everything the page says.
@MainActor
final class ProbeHost: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    struct Event: Encodable { let t: Double; let kind: String; let text: String }

    let window: NSWindow
    let webView: WKWebView
    let scheme: ProbeSchemeHandler
    let outDir: URL
    let started = Date()

    private(set) var events: [Event] = []
    private(set) var errors: [String] = []
    private(set) var downloads: [String] = []
    private(set) var dialogs: [String] = []
    private(set) var webProcessCrashed = false
    var pendingOpenPanel: [URL]?
    var confirmAnswer = false
    var echo = false
    private var navDone: CheckedContinuation<Void, Error>?

    init(size: CGSize, pageRoot: URL, vendorRoot: URL, outDir: URL, config: [String: Any]) throws {
        self.outDir = outDir
        scheme = ProbeSchemeHandler(pageRoot: pageRoot, vendorRoot: vendorRoot)

        let conf = WKWebViewConfiguration()
        conf.websiteDataStore = .nonPersistent()           // no localStorage carried between runs
        conf.setURLSchemeHandler(scheme, forURLScheme: ProbeSchemeHandler.scheme)
        let ucc = conf.userContentController
        let cfgJSON = String(data: try JSONSerialization.data(withJSONObject: config), encoding: .utf8)!
        ucc.addUserScript(WKUserScript(source: "window.__probeConfig=\(cfgJSON);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        guard let jsURL = Bundle.module.url(forResource: "probe", withExtension: "js") else {
            throw ProbeError("probe.js missing from bundle")
        }
        ucc.addUserScript(WKUserScript(source: try String(contentsOf: jsURL, encoding: .utf8), injectionTime: .atDocumentStart, forMainFrameOnly: true))

        webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: conf)
        // The window sits offscreen; without this WebKit treats it as occluded and stops
        // painting and throttles rAF. SPI, test tool only.
        let occlusion = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        if webView.responds(to: occlusion) {
            webView.perform(occlusion, with: nil)          // nil → NO
        }
        // On a real screen (so the display link drives rAF and snapshots) but fully transparent,
        // behind every window and click-through: the user never sees or hits it. Our own events
        // go straight to the window with sendEvent and don't need hit testing.
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        window = ProbeWindow(contentRect: CGRect(x: screen.minX, y: screen.minY, width: size.width, height: size.height),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        super.init()
        ucc.add(self, name: "probe")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(webView)
        try blockNetwork()
    }

    /// Anything http(s) is refused. The page must run from bundled files only.
    private func blockNetwork() throws {
        let rules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
        var compiled: WKContentRuleList?
        var failure: Error?
        let done = DispatchSemaphore(value: 0)
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "lumina-probe-offline", encodedContentRuleList: rules) { list, err in
            compiled = list; failure = err; done.signal()
        }
        while done.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        if let failure { throw failure }
        if let compiled { webView.configuration.userContentController.add(compiled) }
    }

    func log(_ kind: String, _ text: String) {
        let e = Event(t: Date().timeIntervalSince(started), kind: kind, text: text)
        events.append(e)
        if echo || kind == "error" || kind == "pageerror" { FileHandle.standardError.write("[\(kind)] \(text)\n".data(using: .utf8)!) }
    }

    func fail(_ text: String) { errors.append(text); log("error", text) }
    func clearErrors() { errors.removeAll() }

    // MARK: Loading

    func load(_ page: String) async throws {
        let url = URL(string: "\(ProbeSchemeHandler.scheme)://app/\(page.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            navDone = c
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { navDone?.resume(); navDone = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navDone?.resume(throwing: error); navDone = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navDone?.resume(throwing: error); navDone = nil }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webProcessCrashed = true
        fail("web content process terminated (crash or jetsam)")
    }

    // MARK: JS

    @discardableResult
    func js(_ source: String, timeout: TimeInterval = 10) async throws -> Any? {
        try await withThrowingTaskGroup(of: Any?.self) { group in
            group.addTask { @MainActor in try await self.webView.callAsyncJavaScript(source, contentWorld: .page) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
                throw ProbeError("page did not answer within \(timeout)s (hang): \(source.prefix(80))")
            }
            let r = try await group.next()!
            group.cancelAll()
            return r
        }
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        let payload = body["payload"] as? [String: Any] ?? [:]
        switch kind {
        case "console":
            let level = payload["level"] as? String ?? "log"
            let text = payload["text"] as? String ?? ""
            log("console.\(level)", text)
            if level == "error" { fail("console.error: \(text)") }
        case "pageerror":
            fail("page error: \(payload["text"] as? String ?? "?")")
        default:
            log(kind, (try? String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8)) ?? "")
        }
    }

    // MARK: Panels, dialogs, downloads

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        log("openpanel", "dirs=\(parameters.allowsDirectories) multi=\(parameters.allowsMultipleSelection) → \(pendingOpenPanel?.map(\.path) ?? ["cancel"])")
        completionHandler(pendingOpenPanel)
        pendingOpenPanel = nil
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        dialogs.append("confirm: \(message)"); log("dialog", "confirm: \(message) → \(confirmAnswer)")
        completionHandler(confirmAnswer)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        dialogs.append("alert: \(message)"); log("dialog", "alert: \(message)")
        completionHandler()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if action.shouldPerformDownload { return (.download, preferences) }
        if let scheme = action.request.url?.scheme, !["lumina-ref", "about", "blob", "data"].contains(scheme) {
            fail("navigation to \(action.request.url!.absoluteString) blocked")
            return (.cancel, preferences)
        }
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let dir = outDir.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(suggestedFilename)
        try? FileManager.default.removeItem(at: dest)
        downloads.append(dest.path)
        log("download", dest.path)
        return dest
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { fail("download failed: \(error.localizedDescription)") }

    // MARK: Input

    func key(_ name: String, shift: Bool = false, cmd: Bool = false, alt: Bool = false, ctrl: Bool = false, up: Bool = true, down: Bool = true) throws {
        guard let (stroke, impliedShift) = Keys.stroke(name, shift: shift) else { throw ProbeError("unknown key \(name)") }
        var flags: NSEvent.ModifierFlags = []
        if shift || impliedShift { flags.insert(.shift) }
        if cmd { flags.insert(.command) }
        if alt { flags.insert(.option) }
        if ctrl { flags.insert(.control) }
        if ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End", "PageUp", "PageDown", "Delete"].contains(name) {
            flags.formUnion([.numericPad, .function])
        }
        let chars = cmd ? stroke.bare : stroke.chars
        for type in [NSEvent.EventType.keyDown, .keyUp] where (type == .keyDown ? down : up) {
            guard let ev = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: chars,
                                            charactersIgnoringModifiers: stroke.bare, isARepeat: false, keyCode: stroke.code)
            else { throw ProbeError("could not build key event for \(name)") }
            if type == .keyDown, cmd, window.performKeyEquivalent(with: ev) { continue }
            window.sendEvent(ev)
        }
    }

    /// Point in CSS px from the page's top-left.
    func mouse(_ type: NSEvent.EventType, at p: CGPoint, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) {
        let loc = CGPoint(x: p.x, y: webView.bounds.height - p.y)
        guard let ev = NSEvent.mouseEvent(with: type, location: loc, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks,
                                          pressure: type == .leftMouseUp ? 0 : 1) else { return }
        window.sendEvent(ev)
    }

    func scrollWheel(at p: CGPoint, dy: Int32) {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -dy, wheel2: 0, wheel3: 0) else { return }
        cg.location = window.convertPoint(toScreen: CGPoint(x: p.x, y: webView.bounds.height - p.y))
        if let ev = NSEvent(cgEvent: cg) { webView.scrollWheel(with: ev) }
    }

    // MARK: Snapshot

    func snapshot(scale: CGFloat) async throws -> CGImage {
        let conf = WKSnapshotConfiguration()
        conf.afterScreenUpdates = true
        conf.snapshotWidth = NSNumber(value: Double(webView.bounds.width * scale / (window.backingScaleFactor)))
        let image = try await webView.takeSnapshot(configuration: conf)
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { throw ProbeError("snapshot failed") }
        return cg
    }

    /// Web content process id — private KVC, test tool only.
    var webProcessID: pid_t {
        (webView.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value ?? 0
    }
}

final class ProbeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}
