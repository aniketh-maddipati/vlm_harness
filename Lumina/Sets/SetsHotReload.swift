#if DEBUG
import Foundation
import WebKit

/// The dev app's hot reload (Scripts/dev.sh, `LUMINA_HOT=1`). Debug builds only: the Release
/// build has none of this, and the probe and the tests never set the variable.
///
/// A build that changed only the page files or plumbing.js copies them into the running app's
/// bundle. This sees them change, swaps the plumbing user script, reloads the page, and opens the
/// most recent shoot again when the page says it is ready (on launch too, so a relaunch after a
/// Swift change lands in the same shoot). A build that changed Swift relaunches the app: dev.sh.
@MainActor
final class SetsHotReload {
    static var isOn: Bool { ProcessInfo.processInfo.environment["LUMINA_HOT"] == "1" }

    static let files = SetsSchemeHandler.pageFiles + SetsSchemeHandler.vendorFiles + ["plumbing.js"]

    private let root: URL
    private weak var webView: WKWebView?
    private weak var bridge: SetsBridge?
    private var plumbing: String
    /// The files as last looked at, and as the page on screen was loaded from.
    private var seen: String
    private var applied: String
    private var timer: Timer?

    init(root: URL, webView: WKWebView, bridge: SetsBridge, plumbing: String, resume: @escaping @MainActor () -> Void) {
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

    /// Modification time and size of every file the page is made of.
    static func stamp(_ root: URL) -> String {
        files.map { name in
            let a = try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(name).path)
            return "\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) \((a?[.size] as? NSNumber)?.intValue ?? -1)"
        }.joined(separator: "|")
    }

    private func look() {
        let now = Self.stamp(root)
        // A build is still copying: wait until two looks agree.
        guard now == seen else { seen = now; return }
        guard now != applied, let webView else { return }
        applied = now
        let fresh = (try? String(contentsOf: root.appendingPathComponent("plumbing.js"), encoding: .utf8)) ?? plumbing
        if fresh != plumbing {
            // User scripts can't be replaced one at a time: the same list again, in order, with the new plumbing.
            let ucc = webView.configuration.userContentController
            // A copy of our own: WebKit hands out its live list, which removeAllUserScripts empties.
            let scripts = ucc.userScripts.map { $0 }
            ucc.removeAllUserScripts()
            for s in scripts {
                ucc.addUserScript(s.source == plumbing ? WKUserScript(source: fresh, injectionTime: s.injectionTime, forMainFrameOnly: s.isForMainFrameOnly) : s)
            }
            plumbing = fresh
        }
        LuminaLog.app.notice("hot reload: the page files changed")
        bridge?.canvas?.leave()
        webView.load(URLRequest(url: SetsSchemeHandler.pageURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
    }
}
#endif
