import AppKit
import SwiftUI
import WebKit

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

/// Owns the bridge and the web view; answers the page's folder input and downloads; takes the
/// menu bar's items (LuminaApp.swift) to the page.
@MainActor
final class SetsWindowController: NSObject, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate, SetsChooser {
    private(set) var bridge: SetsBridge!
    private(set) var webView: WKWebView?

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
        let exports = Self.supportDir.appendingPathComponent("exports", isDirectory: true)
        Task.detached(priority: .utility) {
            for e in SetsExportJournal.recover(in: exports) {
                NSLog("Lumina: export %@ was cut short: %d of %d done, %d temp files removed", e.id, e.done.count, e.planned.count, e.tempsRemoved ?? 0)
            }
        }
        let res = Bundle.main.resourceURL!
        let plumbing = (try? String(contentsOf: res.appendingPathComponent("plumbing.js"), encoding: .utf8)) ?? ""
        Task { @MainActor in
            do {
                let (wv, _) = try await SetsWebView.make(pageRoot: res, vendorRoot: res, plumbing: plumbing, bridge: bridge,
                                                         standInPhotos: true, config: ["debug": Self.isDebug, "prefs": SetsBridge.prefs ?? NSNull()], frame: host.bounds)
                wv.autoresizingMask = [.width, .height]
                wv.uiDelegate = self
                wv.navigationDelegate = self
                host.addSubview(wv)
                webView = wv
                wv.load(URLRequest(url: SetsSchemeHandler.pageURL))
                host.window?.makeFirstResponder(wv)
                bridge.cards.start()
            } catch {
                NSLog("Lumina: web view setup failed: \(error)")
            }
        }
    }

    // MARK: Menu bar (MENUS.md)

    /// A menu item: the page presses the key it already handles.
    func command(_ name: String) {
        guard name.allSatisfy({ $0.isLetter }) else { return }
        webView?.evaluateJavaScript("window.__lumina && __lumina.command('\(name)')", completionHandler: nil)
    }

    func toggleZoom() { webView?.evaluateJavaScript("window.__lumina && __lumina.zoom()", completionHandler: nil) }

    func reopen(_ id: String) {
        if !bridge.reopen(id: id) { webView?.evaluateJavaScript("window.__lumina && __lumina.say('not available · card out or folder moved')", completionHandler: nil) }
    }

    func closeShoot() { webView?.evaluateJavaScript("window.__lumina && __lumina.closeShoot()", completionHandler: nil) }

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

    /// Keepers whose sidecars aren't written yet (Quit asks). 0 when the page doesn't answer.
    func unsavedKeepers(_ done: @escaping @MainActor (Int) -> Void) {
        guard let webView else { return done(0) }
        webView.evaluateJavaScript("window.__lumina ? __lumina.unsaved() : 0") { value, _ in
            MainActor.assumeIsolated { done((value as? NSNumber)?.intValue ?? 0) }
        }
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

    private func run(_ panel: NSOpenPanel) async -> URL? {
        guard let window = webView?.window else { return panel.runModal() == .OK ? panel.url : nil }
        return await withCheckedContinuation { c in
            panel.beginSheetModal(for: window) { c.resume(returning: $0 == .OK ? panel.url : nil) }
        }
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        Task { @MainActor in completionHandler(await bridge.openPanel(allowsDirectories: parameters.allowsDirectories)) }
    }

    // MARK: Navigation: only our own scheme; downloads land in ~/Downloads

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if action.shouldPerformDownload { return (.download, preferences) }
        guard let url = action.request.url, let scheme = url.scheme, [SetsSchemeHandler.scheme, "about", "blob", "data"].contains(scheme) else {
            // The page's contact links (X, mail) open in the user's browser or mail app, from a click
            // only. The page itself never reaches the network.
            if action.navigationType == .linkActivated, let url = action.request.url, ["https", "mailto"].contains(url.scheme ?? "") {
                NSWorkspace.shared.open(url)
            }
            return (.cancel, preferences)
        }
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var dest = dir.appendingPathComponent(suggestedFilename)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            let stem = (suggestedFilename as NSString).deletingPathExtension, ext = (suggestedFilename as NSString).pathExtension
            dest = dir.appendingPathComponent("\(stem) \(n)" + (ext.isEmpty ? "" : ".\(ext)")); n += 1
        }
        return dest
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The page died (crash or memory). Reload so the window never stays blank.
        webView.load(URLRequest(url: SetsSchemeHandler.pageURL))
    }
}

/// Window sizes: opens at the reference size (1440×900, PARITY.md); minimum 1024×700 (ADDENDUM-1 §4).
enum SetsWindowSize {
    static let initial = CGSize(width: 1440, height: 900)
    static let minimum = CGSize(width: 1024, height: 700)
}

