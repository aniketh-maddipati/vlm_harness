#if DEBUG
import CryptoKit
import Foundation
import WebKit

/// The dev app's hot reload (Scripts/dev.sh, `LUMINA_HOT=1`). Debug builds only: the Release
/// build has none of this, and the probe and the tests never set the variable.
///
/// A build that changed only the page files or plumbing.js copies them into the running app's
/// bundle. This sees them change, swaps the plumbing user script, reloads the page, and opens the
/// most recent shoot again when the page says it is ready (on launch too, so a relaunch after a
/// Swift change lands in the same shoot). A build that changed Swift relaunches the app: dev.sh.
///
/// The files are compared by content, not by date: Scripts/dev-skim.sh copies a page edit straight
/// into the running app (a reload in under a second), and the build that follows copies the same
/// bytes again, which must not reload a second time. Skim has no plumbing (`plumbing` nil).
@MainActor
final class SetsHotReload {
    static var isOn: Bool { ProcessInfo.processInfo.environment["LUMINA_HOT"] == "1" }

    static let files = SetsSchemeHandler.pageFiles + SetsSchemeHandler.vendorFiles + ["plumbing.js"]

    private let root: URL
    private weak var webView: WKWebView?
    private weak var bridge: SetsBridge?
    private var plumbing: String?
    /// The files as last looked at, and as the page on screen was loaded from.
    private var seen: String
    private var applied: String
    private var timer: Timer?

    init(root: URL, webView: WKWebView, bridge: SetsBridge, plumbing: String?, resume: @escaping @MainActor () -> Void) {
        self.root = root
        self.webView = webView
        self.bridge = bridge
        self.plumbing = plumbing
        seen = Self.stamp(root)
        applied = seen
        // The next turn of the loop: "ready" is told from inside the page's own message, before its answer.
        bridge.onEvent = { event in
            guard event == "ready" else { return }
            LuminaLog.app.notice("hot reload: the page is ready")
            DispatchQueue.main.async { resume() }
        }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.look() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// What every file the page is made of holds (a missing file reads as "-"). About 1 MB four
    /// times a second, Debug only.
    static func stamp(_ root: URL) -> String {
        files.map { name in
            guard let d = try? Data(contentsOf: root.appendingPathComponent(name)) else { return "-" }
            return SHA256.hash(data: d).description
        }.joined(separator: "|")
    }

    private func look() {
        let now = Self.stamp(root)
        // A build is still copying: wait until two looks agree.
        guard now == seen else { seen = now; return }
        guard now != applied, let webView else { return }
        applied = now
        if let plumbing, let fresh = try? String(contentsOf: root.appendingPathComponent("plumbing.js"), encoding: .utf8), fresh != plumbing {
            // User scripts can't be replaced one at a time: the same list again, in order, with the new plumbing.
            let ucc = webView.configuration.userContentController
            // A copy of our own: WebKit hands out its live list, which removeAllUserScripts empties.
            let scripts = ucc.userScripts.map { $0 }
            ucc.removeAllUserScripts()
            for s in scripts {
                ucc.addUserScript(s.source == plumbing ? WKUserScript(source: fresh, injectionTime: s.injectionTime, forMainFrameOnly: s.isForMainFrameOnly) : s)
            }
            self.plumbing = fresh
        }
        LuminaLog.app.notice("hot reload: the page files changed")
        bridge?.canvas?.leave()
        webView.load(URLRequest(url: SetsSchemeHandler.pageURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
    }
}
#endif
