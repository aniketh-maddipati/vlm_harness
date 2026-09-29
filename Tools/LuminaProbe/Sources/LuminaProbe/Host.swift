import AppKit
import WebKit

/// One offscreen window holding one WKWebView — the same engine and the same key/mouse path
/// (NSEvent → first responder) the app uses. Collects everything the page says.
@MainActor
final class ProbeHost: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    struct Event: Encodable { let t: Double; let kind: String; let text: String }

    let window: NSWindow
    let webView: WKWebView
    let scheme: SetsSchemeHandler
    /// App mode: the app's own bridge + plumbing.js. Prototype mode: nil, the page as designed.
    let bridge: SetsBridge?
    var chooser: ProbeChooser { chooserRef! }
    let outDir: URL
    let started = Date()

    private(set) var events: [Event] = []
    private(set) var errors: [String] = []
    private(set) var downloads: [String] = []
    private(set) var dialogs: [String] = []
    private(set) var webProcessCrashed = false
    var pendingOpenPanel: [URL]? {
        get { chooser.sources.first.map { [$0] } }
        set { chooser.sources = newValue ?? [] }
    }
    var confirmAnswer = false
    var echo = false
    private var navDone: CheckedContinuation<Void, Error>?

    static func make(size: CGSize, pageRoot: URL, vendorRoot: URL, plumbing: URL?, supportDir: URL,
                     outDir: URL, config: [String: Any], appConfig: [String: Any] = [:]) async throws -> ProbeHost {
        let cfgJSON = String(data: try JSONSerialization.data(withJSONObject: config), encoding: .utf8)!
        guard let jsURL = Bundle.module.url(forResource: "probe", withExtension: "js") else { throw ProbeError("probe.js missing from bundle") }
        let probeJS = try String(contentsOf: jsURL, encoding: .utf8)
        let chooserHolder = ProbeChooser()
        var bridge: SetsBridge?
        var plumbingJS = ""
        if let plumbing {
            plumbingJS = try String(contentsOf: plumbing, encoding: .utf8)
            bridge = SetsBridge(chooser: chooserHolder, supportDir: supportDir)
        }
        let (wv, scheme) = try await SetsWebView.make(pageRoot: pageRoot, vendorRoot: vendorRoot, plumbing: plumbingJS, bridge: bridge,
                                                      standInPhotos: true, config: appConfig, extraScripts: ["window.__probeConfig=\(cfgJSON);", probeJS],
                                                      frame: CGRect(origin: .zero, size: size))
        return ProbeHost(webView: wv, scheme: scheme, bridge: bridge, chooser: chooserHolder, size: size, outDir: outDir)
    }

    private init(webView: WKWebView, scheme: SetsSchemeHandler, bridge: SetsBridge?, chooser: ProbeChooser, size: CGSize, outDir: URL) {
        self.webView = webView
        self.scheme = scheme
        self.bridge = bridge
        self.outDir = outDir
        // The window sits where the user can't see it; without this WebKit treats it as occluded
        // and stops painting and throttles rAF. SPI, test tool only.
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
        self.chooserRef = chooser
        webView.configuration.userContentController.add(self, name: "probe")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(webView)
        bridge?.onEvent = { [weak self] in self?.log("bridge", $0) }
    }

    private var chooserRef: ProbeChooser?

    func log(_ kind: String, _ text: String) {
        let e = Event(t: Date().timeIntervalSince(started), kind: kind, text: text)
        events.append(e)
        if echo || kind == "error" || kind == "pageerror" { FileHandle.standardError.write("[\(kind)] \(text)\n".data(using: .utf8)!) }
    }

    func fail(_ text: String) { errors.append(text); log("error", text) }
    func clearErrors() { errors.removeAll() }

    // MARK: Loading

    func load(_ page: String) async throws {
        let url = URL(string: "\(SetsSchemeHandler.scheme)://app/\(page.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!
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
        if let bridge {
            Task { @MainActor in completionHandler(await bridge.openPanel(allowsDirectories: parameters.allowsDirectories)) }
        } else {
            completionHandler(pendingOpenPanel)
            pendingOpenPanel = nil
        }
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
        if let scheme = action.request.url?.scheme, ![SetsSchemeHandler.scheme, "about", "blob", "data"].contains(scheme) {
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
        // Straight to the web view: NSWindow.sendEvent drops mouse events for a window that isn't
        // under the pointer / ignores mouse events.
        switch type {
        case .leftMouseDown: webView.mouseDown(with: ev)
        case .leftMouseUp: webView.mouseUp(with: ev)
        case .leftMouseDragged: webView.mouseDragged(with: ev)
        case .mouseMoved: webView.mouseMoved(with: ev)
        default: window.sendEvent(ev)
        }
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

/// Scripted answers for the bridge's folder pickers. Each pick consumes the next queued URL; an
/// empty queue means the user pressed Cancel. Refusals are recorded for assertions.
@MainActor
final class ProbeChooser: SetsChooser {
    var sources: [URL] = []
    var destinations: [URL] = []
    private(set) var refusals: [String] = []
    private(set) var asked: [String] = []

    func chooseSource(allowsDirectories: Bool) async -> URL? {
        asked.append("source")
        return sources.isEmpty ? nil : sources.removeFirst()
    }

    func chooseDestination(label: String, suggested: URL?, refusal: String?) async -> URL? {
        asked.append("destination:\(label)")
        if let refusal { refusals.append(refusal) }
        return destinations.isEmpty ? nil : destinations.removeFirst()
    }
}
