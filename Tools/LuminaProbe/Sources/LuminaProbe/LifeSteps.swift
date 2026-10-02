import AppKit
import Darwin
import WebKit

/// Lifecycle steps (release task Q3, `bash Scripts/probe.sh life`). The kill-anywhere loop needs
/// none of these: it kills the whole probe process from outside (probe.sh's life helper). These
/// are the parts that happen inside one process:
///
///   recovery        {limit?, windowS?}  answer a stopped page with the app's own SetsReloadPolicy
///                   (Host.swift; SetsPageRecovery.swift is compiled in), not a run failure.
///   killWebContent  {expect: "reload" | "ask", tryAgain?, timeoutMs?}  SIGKILL this probe's own web
///                   content process (the pid WebKit reports for this probe's web view, checked to be
///                   a WebContent process: never any other WebKit process on the Mac), then wait for
///                   the recovery's answer and, on a reload, for the page to be ready again.
///   quitHung        {hangMs?, timeoutS?, expectAnswer?}  the Quit question (LuminaAppDelegate →
///                   SetsRootView.unsavedKeepers) asked of this page, through the app's own
///                   SetsFirstAnswer with its 2 s timeout: once answered (`expectAnswer`), once with
///                   the page's main thread held in a busy loop for `hangMs`. The question's closure is
///                   repeated from SetsRootView (5 lines); the app delegate itself is not in the probe.
@MainActor
enum LifeSteps {
    static func run(_ op: String, _ s: [String: Any], host: ProbeHost) async throws -> String? {
        switch op {
        case "recovery":
            let limit = s["limit"] as? Int ?? SetsReloadPolicy.limit, window = s["windowS"] as? Double ?? SetsReloadPolicy.window
            host.recovery = SetsReloadPolicy(limit: limit, window: window)
            return "a stopped page reloads up to \(limit)× in \(Int(window)) s, then asks"
        case "killWebContent":
            return try await killWebContent(s, host: host)
        case "quitHung":
            return try await quitHung(s, host: host)
        case "expectDump":
            // The page's answer now equals what an earlier `dump` step saved (a page that died since).
            guard let name = s["name"] as? String, let js = s["js"] as? String else { throw ProbeError("expectDump needs name and js") }
            let url = host.outDir.appendingPathComponent("\(name).json")
            let saved = try ProbeSandbox.harness { try String(contentsOf: url, encoding: .utf8) }
            // `js` returns a string (as the dump's did, saved verbatim): compared byte for byte.
            let now = try await host.js(js) as? String ?? "nil"
            guard now == saved else { throw ProbeError("now \(now), \(name) had \(saved)") }
            return "equal to \(name)"
        case "sidecarsWhole":
            // After an interrupted Save: the .xmp count is one of `oneOf` (none or all, never some),
            // every .xmp parses and carries a rating, and no temp file is left.
            guard let dir = (s["dir"] as? String).map({ URL(fileURLWithPath: $0.replacingOccurrences(of: "${OUT}", with: host.outDir.path)) }) else { throw ProbeError("sidecarsWhole needs dir") }
            return try ProbeSandbox.harness {
                let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                let xmp = names.filter { $0.lowercased().hasSuffix(".xmp") }.sorted()
                if let temp = names.first(where: { $0.contains(".lumina-tmp-") }) { throw ProbeError("temp file left: \(temp)") }
                for n in xmp {
                    let data = try Data(contentsOf: dir.appendingPathComponent(n))
                    guard XMLParser(data: data).parse(), String(decoding: data, as: UTF8.self).contains("xmp:Rating") else { throw ProbeError("\(n) is torn") }
                }
                if let allowed = s["oneOf"] as? [Int], !allowed.contains(xmp.count) { throw ProbeError("\(xmp.count) sidecars (\(xmp)), want one of \(allowed)") }
                let baks = names.filter { $0.hasSuffix(SetsFileOps.backupSuffix) }.count
                return "\(xmp.count) sidecars, all whole · \(baks) .lumina-bak · no temp file"
            }
        default:
            throw ProbeError("unknown life step \(op)")
        }
    }

    private static func procPath(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
    }

    private static func ready(_ host: ProbeHost, timeout: TimeInterval) async throws {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let r = try? await host.js("return !!(window.__probe && __probe.ready())", timeout: 3) as? Bool, r { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw ProbeError("page not ready \(Int(timeout)) s after the web content process was killed")
    }

    private static func killWebContent(_ s: [String: Any], host: ProbeHost) async throws -> String {
        guard host.recovery != nil else { throw ProbeError("killWebContent needs a recovery step first") }
        let pid = host.webProcessID
        let path = procPath(pid)
        // Only this probe's own web view's process, and only if it is a WebContent process.
        // (Sandboxed, proc_pidpath may be refused; the launcher checks the path before it kills.)
        guard pid > 0, pid != getpid(), ProbeSandbox.active || path.contains("WebContent") else { throw ProbeError("no web content process of this probe to kill (pid \(pid), \(path))") }
        let before = host.recoveries.count
        let t0 = Date()
        // Sandboxed, the probe may not signal it (EPERM): its unsandboxed launcher sends the kill.
        if let r = ProbeSandbox.killWebContent(pid) {
            guard r == "killed" else { throw ProbeError("launcher could not kill web content pid \(pid): \(r)") }
        } else {
            guard kill(pid, SIGKILL) == 0 else { throw ProbeError("kill(\(pid)) refused: \(String(cString: strerror(errno)))") }
        }
        host.log("life", "killed web content pid \(pid)\(ProbeSandbox.active ? " (through the launcher)" : "")")
        let timeout = (s["timeoutMs"] as? Double ?? 15000) / 1000
        while host.recoveries.count == before {
            if Date().timeIntervalSince(t0) > timeout { throw ProbeError("web content pid \(pid) killed, no terminate callback within \(Int(timeout)) s") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let got = host.recoveries[before]
        let tCallback = Date().timeIntervalSince(t0) * 1000
        if let want = s["expect"] as? String, want != got { throw ProbeError("expected \(want) after the kill, got \(got) (recoveries so far: \(host.recoveries))") }
        var note = "killed web content pid \(pid) → \(got) after \(Int(tCallback)) ms"
        if got == "reload" {
            try await ready(host, timeout: timeout + 30)
            note += String(format: " · page ready %.0f ms after the kill · new pid %d", Date().timeIntervalSince(t0) * 1000, host.webProcessID)
        }
        // Nothing may stop or reload on its own afterwards (no loop): one kill, one answer.
        let quiet = s["quietMs"] as? Double ?? 1000
        try await Task.sleep(nanoseconds: UInt64(quiet * 1_000_000))
        if host.recoveries.count != before + 1 { throw ProbeError("more stops after one kill: \(Array(host.recoveries.dropFirst(before)))") }
        if got == "ask" {
            if host.webView.isLoading || host.webProcessID != 0 { throw ProbeError("asked, yet the page is loading again (pid \(host.webProcessID))") }
            note += String(format: " · nothing reloaded in %.0f ms", quiet)
            if s["tryAgain"] as? Bool ?? false {
                let t1 = Date()
                host.recoveryTryAgain()
                try await ready(host, timeout: timeout + 30)
                note += String(format: " · Try Again: page ready in %.0f ms, count reset", Date().timeIntervalSince(t1) * 1000)
            }
        }
        return note
    }

    private static func quitHung(_ s: [String: Any], host: ProbeHost) async throws -> String {
        let timeout = s["timeoutS"] as? Double ?? 2       // SetsRootView.unsavedKeepersTimeout
        // As SetsRootView.unsavedKeepers asks it (the closure is the app's, repeated).
        func ask() async -> (Int, Double) {
            let t0 = Date()
            let n: Int = await withCheckedContinuation { c in
                SetsFirstAnswer<Int>.ask(timeout: timeout, fallback: 0, schedule: { after, fire in
                    RunLoop.main.add(Timer(timeInterval: after, repeats: false) { _ in MainActor.assumeIsolated { fire() } }, forMode: .common)
                }, question: { answer in
                    host.webView.evaluateJavaScript("window.__lumina ? __lumina.unsaved() : 0") { value, _ in
                        MainActor.assumeIsolated { _ = answer((value as? NSNumber)?.intValue ?? 0) }
                    }
                }, done: { c.resume(returning: $0) })
            }
            return (n, Date().timeIntervalSince(t0) * 1000)
        }
        let (live, liveMs) = await ask()
        if let want = s["expectAnswer"] as? Int, want != live { throw ProbeError("page answered \(live) unsaved keepers, want \(want)") }
        // Hold the page's main thread, then ask again: the answer must be the fallback, in about 2 s.
        let hang = s["hangMs"] as? Double ?? 6000
        host.webView.evaluateJavaScript("window.__q3hang = Date.now(); while (Date.now() - window.__q3hang < \(Int(hang))) {} 0", completionHandler: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        let (hung, hungMs) = await ask()
        let note = String(format: "answered: %d unsaved in %.0f ms · page held: answer %d after %.0f ms (timeout %.1f s)", live, liveMs, hung, hungMs, timeout)
        if hungMs > timeout * 1000 + 500 || hungMs < timeout * 1000 - 100 { throw ProbeError("Quit question with the page held took \(Int(hungMs)) ms, want about \(timeout) s: \(note)") }
        if hung != 0 { throw ProbeError("a held page answered \(hung): \(note)") }
        // Let the busy loop end before the next step talks to the page.
        try await ready(host, timeout: hang / 1000 + 10)
        return note
    }
}
