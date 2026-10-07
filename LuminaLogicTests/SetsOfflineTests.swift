import Foundation
import XCTest
@testable import Lumina

/// The page's offline layers (docs/release/TRUST.md I5) stay what they say: every load blocked but
/// the page's own schemes, a CSP that names no network source and allows no frames, plugins or
/// form posts (workers only from blob:), and WebRTC gone. Foundation only, run on Linux too; the layers at work
/// are Tests/web/webkit.py offline (WebKitGTK) and the probe's app-offline (WKWebView).
final class SetsOfflineTests: XCTestCase {
    func testRulesBlockEverythingButThePagesOwnSchemes() throws {
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(SetsOffline.contentRules.utf8)) as? [[String: [String: String]]])
        XCTAssertEqual(rules.first?["trigger"]?["url-filter"], ".*")
        XCTAssertEqual(rules.first?["action"]?["type"], "block")
        let through = rules.dropFirst().map { $0["trigger"]?["url-filter"] ?? "" }
        XCTAssertEqual(Set(through), ["^lumina:", "^blob:", "^data:", "^about:"])
        XCTAssertTrue(rules.dropFirst().allSatisfy { $0["action"]?["type"] == "ignore-previous-rules" && $0["trigger"]?.count == 1 },
                      "a rule that lets a load through names only a scheme")
    }

    func testCSPNamesNoNetworkSource() {
        let csp = SetsOffline.contentSecurityPolicy
        var d: [String: [String]] = [:]
        for part in csp.split(separator: ";") {
            let w = part.split(separator: " ").map(String.init)
            if let k = w.first { d[k] = Array(w.dropFirst()) }
        }
        XCTAssertEqual(d["default-src"], ["'none'"])
        for k in ["frame-src", "child-src", "object-src", "manifest-src", "base-uri", "form-action"] { XCTAssertEqual(d[k], ["'none'"], k) }
        XCTAssertEqual(d["worker-src"], ["blob:"], "workers only from the page's own code")
        let allowed: Set<String> = ["lumina:", "blob:", "data:", "'none'", "'unsafe-inline'", "'unsafe-eval'"]
        for (k, v) in d { XCTAssertTrue(Set(v).isSubset(of: allowed), "\(k): \(v)") }
        XCTAssertFalse(csp.contains("\n"), "one header line")
        XCTAssertEqual(SetsOffline.pageHeaders["Content-Security-Policy"], csp)
    }

    func testScriptRemovesWebRTC() {
        for n in ["RTCPeerConnection", "webkitRTCPeerConnection", "RTCDataChannel"] { XCTAssertTrue(SetsOffline.pageScript.contains("'\(n)'"), n) }
        XCTAssertTrue(SetsOffline.pageScript.contains("configurable: false"), "a page can't put them back")
    }
}
