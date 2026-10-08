import AppKit
import UniformTypeIdentifiers
import SwiftUI
import WebKit
import os

/// The whole app window: one WKWebView showing the design's page, full window, no browser chrome.
struct SetsRootView: NSViewRepresentable {
    func makeCoordinator() -> SetsWindowController { SetsWindowController() }

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        context.coordinator.attach(to: host)
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Owns the bridge and the web view (and, through the bridge, the Edit canvas overlay); answers
/// the page's folder input and downloads; takes the menu bar's items (LuminaApp.swift) to the page.
@MainActor
final class SetsWindowController: NSObject, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate, NSOpenSavePanelDelegate, SetsChooser {
    private(set) var bridge: SetsBridge!
    private(set) var webView: WKWebView?
    #if DEBUG
    /// Scripts/dev.sh (`LUMINA_HOT=1`): the page reloads when a build changes its files.
    private var hotReload: SetsHotReload?
    #endif

    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lumina", isDirectory: true)
    }

    func attach(to host: NSView) {
        bridge = SetsBridge(chooser: self, supportDir: Self.supportDir)
        SetsMenuModel.shared.controller = self
        bridge.onShootsChanged = { [weak self] in self?.refreshRecents() }
        refreshRecents()
        // An export cut short last time (crash, kill, power): clear its temp files, keep its journal.
        // The destination is reached through the journal's bookmark (the panel's grant died with
        // the last process); when that fails the files stay and the journal says why.
        // The page says so once on Open (CHANGES-v0.04 D3: `lumina.cutShort`), so this runs before it loads;
        // with no export cut short it is one directory listing.
        let exports = Self.supportDir.appendingPathComponent("exports", isDirectory: true)
        let res = Bundle.main.resourceURL!
        // Skim (a Debug build with LUMINA_PAGE=skim) has no plumbing yet: the page runs on its own.
        let page = SetsPage.current
        let plumbing = page == .pick ? ((try? String(contentsOf: res.appendingPathComponent("plumbing.js"), encoding: .utf8)) ?? "") : ""
        Task { @MainActor in
            let cut = await Task.detached(priority: .userInitiated) { () -> [(folder: String, done: Int, planned: Int, cleaned: Bool)] in
                SetsExportJournal.recover(in: exports).map { e in
                    if let why = e.recoveryRefused {
                        LuminaLog.export.error("export \(e.id, privacy: .public) was cut short: \(e.done.count, privacy: .public) of \(e.planned.count, privacy: .public) done, temp files left: \(why, privacy: .private)")
                    } else {
                        LuminaLog.export.notice("export \(e.id, privacy: .public) was cut short: \(e.done.count, privacy: .public) of \(e.planned.count, privacy: .public) done, \(e.tempsRemoved ?? 0, privacy: .public) temp files removed")
                    }
                    return (URL(fileURLWithPath: e.destination).lastPathComponent, e.done.count, e.planned.count, e.recoveryRefused == nil)
                }
            }.value.map { ["folder": $0.folder, "done": $0.done, "planned": $0.planned, "cleaned": $0.cleaned] as [String: Any] }
            do {
                let (wv, _) = try await SetsWebView.make(pageRoot: res, vendorRoot: res, plumbing: plumbing, bridge: bridge,
                                                         standInPhotos: true, config: ["debug": Self.isDebug, "prefs": SetsBridge.prefs.map { $0 as Any } ?? NSNull(), "cutShort": cut],
                                                         extraScripts: page == .skim ? [SetsPage.skimHostScript] : [], frame: host.bounds)
                wv.autoresizingMask = [.width, .height]
                wv.uiDelegate = self
                wv.navigationDelegate = self
                host.addSubview(wv)
                webView = wv
                // The Edit canvas: the one native view over the page (AGENTS.md), above the web view.
                if page == .pick { bridge.attachCanvas(host: host) }
                wv.load(URLRequest(url: SetsSchemeHandler.pageURL))
                host.window?.makeFirstResponder(wv)
                if page == .pick {
                    bridge.cards.start()
                    offerEarlierSessions()
                }
                #if DEBUG
                if SetsHotReload.isOn {
                    hotReload = SetsHotReload(root: res, webView: wv, bridge: bridge, plumbing: page == .pick ? plumbing : nil) { [weak self] in
                        guard let self, let last = self.bridge.shoots.index().first else { return }
                        self.reopen(last.id)
                    }
                }
                #endif
            } catch {
                LuminaLog.app.fault("web view setup failed: \(String(describing: error), privacy: .private)")
            }
        }
    }

    // MARK: Menu bar (MENUS.md)

    /// A menu item: the page presses the key it already handles.
    func command(_ name: String) {
        guard name.allSatisfy({ $0.isLetter }) else { return }
        if SetsPage.current == .skim {
            if let js = SetsPage.skimKeyScript(for: name) { webView?.evaluateJavaScript(js, completionHandler: nil) }
            return
        }
        webView?.evaluateJavaScript("window.__lumina && __lumina.command('\(name)')", completionHandler: nil)
    }

    func toggleZoom() { webView?.evaluateJavaScript("window.__lumina && __lumina.zoom()", completionHandler: nil) }

    func reopen(_ id: String) {
        guard !bridge.reopen(id: id) else { return }
        // A recent brought over from before the sandbox has no bookmark until its folder is opened once (R1e).
        let imported = bridge.shoots.index().first(where: { $0.id == id }).map { $0.bookmark == nil } ?? false
        say(imported ? SetsEarlierSessions.recentNeedsFolder : "not available · card out or folder moved")
    }

    /// One line in the page's status line.
    private func say(_ line: String) {
        guard let data = try? JSONEncoder().encode(line), let js = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__lumina && __lumina.say(\(js))", completionHandler: nil)
    }

    /// The page saves and forgets the shoot; then its folder's access is stopped (SetsAccess).
    func closeShoot() {
        // Skim: ⌘W is the page's own Close (it asks first, then goes back to Open).
        if SetsPage.current == .skim {
            if let js = SetsPage.skimKeyScript(for: "closeShoot") { webView?.evaluateJavaScript(js, completionHandler: nil) }
            return
        }
        guard let webView else { bridge.closeShoot(); return }
        webView.evaluateJavaScript("window.__lumina && __lumina.closeShoot()") { [weak self] _, _ in self?.bridge.closeShoot() }
    }

    /// File ▸ Remove Working Files…: Lumina's own session files for the open shoot. Never photos or sidecars.
    func confirmRemoveWorkingFiles() {
        let alert = NSAlert()
        alert.messageText = "Remove Lumina's working files for this shoot?"
        alert.informativeText = "Your decisions for it are forgotten. Photos and sidecars stay where they are."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        webView?.evaluateJavaScript("window.__lumina && __lumina.removeWorkingFiles()", completionHandler: nil)
    }

    /// How long Quit waits for the page before going ahead without its answer.
    static let unsavedKeepersTimeout: TimeInterval = 2

    /// False when there is no page to ask: no web view yet, or it stopped and was not reloaded.
    var pageCanAnswer: Bool { webView != nil && !pageStopped }

    /// Keepers whose sidecars aren't written yet (Quit asks). 0 when the page doesn't answer
    /// within 2 seconds (hung or dead). `done` is called exactly once, whichever comes first.
    func unsavedKeepers(_ done: @escaping @MainActor (Int) -> Void) {
        guard let webView, !pageStopped else { return done(0) }
        SetsFirstAnswer<Int>.ask(timeout: Self.unsavedKeepersTimeout, fallback: 0, schedule: { after, fire in
            // Common modes: while Quit waits (.terminateLater) the app runs its loop in the modal panel mode.
            RunLoop.main.add(Timer(timeInterval: after, repeats: false) { _ in MainActor.assumeIsolated { fire() } }, forMode: .common)
        }, question: { answer in
            webView.evaluateJavaScript("window.__lumina ? __lumina.unsaved() : 0") { value, _ in
                MainActor.assumeIsolated { answer((value as? NSNumber)?.intValue ?? 0) }
            }
        }, done: done)
    }

    func refreshRecents() {
        SetsMenuModel.shared.recents = bridge.shoots.index().prefix(10).map { SetsMenuModel.Recent(id: $0.id, title: $0.path.hasPrefix("/Volumes/") ? $0.path : ($0.path as NSString).abbreviatingWithTildeInPath) }
    }

    // MARK: SetsChooser (NSOpenPanel)

    func chooseSource(allowsDirectories: Bool) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder of ARWs. Lumina only reads it."
        return await run(panel)
    }

    /// Skim's panel: a card, folders, or clips picked one by one. Sony's sidecars come with a folder or a card.
    func chooseClips() async -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie] + [UTType(filenameExtension: "mxf"), UTType(filenameExtension: "m4v")].compactMap { $0 }
        panel.prompt = "Open"
        panel.message = "Choose a card, a folder or clips: MP4, MOV, MXF, M4V. Lumina only reads them."
        guard let window = webView?.window else { return panel.runModal() == .OK ? panel.urls : nil }
        return await withCheckedContinuation { c in
            panel.beginSheetModal(for: window) { c.resume(returning: $0 == .OK ? panel.urls : nil) }
        }
    }

    func chooseDestination(label: String, suggested: URL?, refusal: String?) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export here"
        panel.message = refusal ?? (label == "xmp" ? "Choose the folder for the .xmp sidecars." : "Choose where the export goes.")
        panel.directoryURL = suggested
        return await run(panel)
    }

    func chooseCard(name: String, at: URL, refusal: String?) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Cull This Card"
        panel.message = refusal ?? "Choose the card \(name) to let Lumina read it. Lumina only reads it, and remembers this card."
        panel.directoryURL = at
        return await run(panel)
    }

    private func run(_ panel: NSOpenPanel) async -> URL? {
        guard let window = webView?.window else { return panel.runModal() == .OK ? panel.url : nil }
        return await withCheckedContinuation { c in
            panel.beginSheetModal(for: window) { c.resume(returning: $0 == .OK ? panel.url : nil) }
        }
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        // Skim reads clips through the page's own file input: a card, folders or clips, nothing else of Pick's.
        if SetsPage.current == .skim { Task { @MainActor in completionHandler(await chooseClips()) }; return }
        Task { @MainActor in completionHandler(await bridge.openPanel(allowsDirectories: parameters.allowsDirectories)) }
    }

    // MARK: Navigation: only our own scheme; downloads go through a save panel

    /// The page is only ever `lumina://`; frames it makes may be about:blank (the CSP allows no
    /// others). Anything else is never loaded here: a link the user clicked to one of the three
    /// destinations `SetsExternalLinks` names (Report a bug, LinkedIn, X) is rebuilt and handed to
    /// their mail app or browser; every other URL is refused (docs/release/TRUST.md I5).
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if action.shouldPerformDownload { return (.download, preferences) }
        guard let url = action.request.url else { return (.cancel, preferences) }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == SetsSchemeHandler.scheme || scheme == "about" { return (.allow, preferences) }
        if ["blob", "data"].contains(scheme), let frame = action.targetFrame, !frame.isMainFrame { return (.allow, preferences) }
        switch SetsExternalLinks.verdict(for: url, userClicked: action.navigationType == .linkActivated) {
        case .external(let safe):
            NSWorkspace.shared.open(safe)
        case .refuse(let why):
            LuminaLog.app.error("navigation refused (\(why, privacy: .public)): \(url.absoluteString, privacy: .private)")
        case .inPage:
            break
        }
        return (.cancel, preferences)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    /// The page's downloads (its debug "lumina-golden.json"; the browser-only xmp zip never runs in
    /// the app) go where the user puts them in a save panel, never straight into ~/Downloads: the
    /// sandboxed app has no Downloads entitlement, and the page doesn't get to pick a place (R1d,
    /// THREAT-MODEL T11). The panel's grant covers exactly the file chosen. A file already there is
    /// not replaced (no room for a .lumina-bak beside it in the sandbox): the panel asks for another name.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.safeDownloadName(suggestedFilename)
        panel.canCreateDirectories = true
        panel.delegate = self
        guard let window = webView?.window else { return panel.runModal() == .OK ? panel.url : nil }
        return await withCheckedContinuation { c in
            panel.beginSheetModal(for: window) { c.resume(returning: $0 == .OK ? panel.url : nil) }
        }
    }

    /// The page's suggested name as one plain file name: no folders, no leading dot, no control
    /// characters, at most 128 characters.
    nonisolated static func safeDownloadName(_ suggested: String) -> String {
        let last = suggested.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        var name = String(String.UnicodeScalarView(last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" }))
        while let f = name.first, f == "." || f.isWhitespace { name.removeFirst() }
        name = String(name.prefix(128)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "lumina-download" : name
    }

    /// The download's save panel: an existing file is refused (WKDownload would fail on it, and
    /// replacing it would leave no .lumina-bak).
    func panel(_ sender: Any, validate url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError, userInfo: [NSFilePathErrorKey: url.path, NSURLErrorKey: url])
    }

    // MARK: Sessions from before the sandbox (R1e)

    /// Launch, once: while this store has never been used and the question was never answered,
    /// offer to bring over the sessions of the build before the sandbox. Never under XCTest (the
    /// logic tests are hosted in the app). A sheet on the window, so nothing blocks the launch; no
    /// window within 10 s means no question this time.
    private func offerEarlierSessions() {
        guard !SetsEarlierSessions.underTest, bridge.shoots.offersImport else { return }
        Task { @MainActor in
            for _ in 0..<40 {
                if let window = webView?.window { askAboutEarlierSessions(on: window); return }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func askAboutEarlierSessions(on window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = SetsEarlierSessions.message
        alert.informativeText = SetsEarlierSessions.detail
        alert.addButton(withTitle: SetsEarlierSessions.choose)
        alert.addButton(withTitle: SetsEarlierSessions.notNow)
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                if response == .alertFirstButtonReturn { self.bringOverEarlierSessions() }
                else { try? self.bridge.shoots.markImportAsked() }      // Not Now: never asked again by itself
            }
        }
    }

    /// The folder panel on the earlier build's support folder, then the import
    /// (`SetsShootStore.importStore`, which only reads that folder). A pick without
    /// `shoots/index.json` is refused in the panel's own message and the panel asks again; Cancel
    /// leaves everything as it was (the launch question comes back next time). The panel's grant
    /// is all the access there is: no bookmark to that folder is kept.
    func bringOverEarlierSessions() {
        Task { @MainActor in
            var refusal: String?
            while true {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = false
                panel.allowsMultipleSelection = false
                panel.prompt = SetsEarlierSessions.panelPrompt
                panel.message = refusal ?? SetsEarlierSessions.panelMessage
                panel.directoryURL = SetsEarlierSessions.earlierSupportDir
                guard let picked = await run(panel) else { return }
                let store = bridge.shoots
                // Off the main thread: a store can hold many sessions of several megabytes.
                let (imported, failure) = await Task.detached(priority: .userInitiated) { () -> (SetsShootStore.ImportResult?, String?) in
                    guard let old = SetsShootStore.earlierStore(in: picked) else { return (nil, nil) }
                    do { return (try store.importStore(from: old), nil) } catch { return (nil, "\(error)") }
                }.value
                if let failure {
                    LuminaLog.app.error("earlier sessions not brought over: \(failure, privacy: .private)")
                    say(SetsEarlierSessions.failed(failure))
                    return
                }
                guard let result = imported else { refusal = SetsEarlierSessions.panelRefusal; continue }
                let skipped = result.skipped.map { "\($0.key.rawValue) \($0.value)" }.sorted().joined(separator: ", ")
                LuminaLog.app.notice("earlier sessions: \(result.sessions, privacy: .public) sessions, \(result.headers, privacy: .public) headers, \(result.recents, privacy: .public) recents brought over; \(result.alreadyHere, privacy: .public) already here, \(result.keptNewer, privacy: .public) kept as they are here; skipped \(skipped, privacy: .public)")
                try? bridge.shoots.markImportAsked()
                refreshRecents()
                webView?.evaluateJavaScript("window.__lumina && __lumina.recents()", completionHandler: nil)
                say(result.statusLine)
                return
            }
        }
    }

    // MARK: The page stopped (crash or memory)

    private var reloadPolicy = SetsReloadPolicy()
    /// The page stopped and was not reloaded: the alert is up, or was answered with Quit.
    private(set) var pageStopped = false

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !pageStopped else { return }
        switch reloadPolicy.pageStopped() {
        case .reload:
            // Reload so the window never stays blank.
            webView.load(URLRequest(url: SetsSchemeHandler.pageURL))
        case .ask:
            // It keeps stopping (a file that kills the page would loop forever): ask, once.
            let (limit, secs) = (reloadPolicy.limit, reloadPolicy.window)
            LuminaLog.app.fault("the page stopped again after \(limit, privacy: .public) reloads in \(secs, format: .fixed(precision: 0), privacy: .public) s; not reloading")
            pageStopped = true
            askAboutStoppedPage(webView)
        }
    }

    /// Decisions are already on disk (the bridge's `saveSession`), so both answers are safe.
    private func askAboutStoppedPage(_ webView: WKWebView) {
        let alert = NSAlert()
        alert.messageText = SetsPageStoppedAlert.message
        alert.informativeText = SetsPageStoppedAlert.detail(limit: reloadPolicy.limit)
        alert.addButton(withTitle: SetsPageStoppedAlert.tryAgain)
        alert.addButton(withTitle: SetsPageStoppedAlert.quit)
        let answered: (NSApplication.ModalResponse) -> Void = { [weak self, weak webView] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn else { NSApp.terminate(nil); return }
                guard let self else { return }
                self.reloadPolicy.reset()
                self.pageStopped = false
                webView?.load(URLRequest(url: SetsSchemeHandler.pageURL))
            }
        }
        // Not a modal loop inside WebKit's callback: a sheet on the window, or the next turn of the loop.
        if let window = webView.window {
            alert.beginSheetModal(for: window, completionHandler: answered)
        } else {
            DispatchQueue.main.async { answered(alert.runModal()) }
        }
    }
}

/// Window sizes: opens at the reference size (1440×900, PARITY.md); minimum 1024×700 (ADDENDUM-1 §4).
enum SetsWindowSize {
    static let initial = CGSize(width: 1440, height: 900)
    static let minimum = CGSize(width: 1024, height: 700)
}

