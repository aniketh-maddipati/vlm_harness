import CryptoKit
import XCTest

/// The app ships the design's page unchanged (BUILD-exact rule 1). The bundled copies in
/// Lumina/Sets/Web must be byte-identical to design/handoff; run Scripts/sets_sync_ui.sh after a
/// new handoff.
final class SetsPageBytesTests: XCTestCase {
    func testBundledPageMatchesTheDesign() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let pairs: [(String, String)] = [
            ("design/handoff/lumina-cull/Lumina Sets v3.dc.html", "Lumina/Sets/Web/Lumina Sets v3.dc.html"),
            ("design/handoff/lumina-cull/support.js", "Lumina/Sets/Web/support.js"),
            ("design/handoff/lumina-cull/lumina-core.js", "Lumina/Sets/Web/lumina-core.js"),
            ("design/handoff/vendor/react.production.min.js", "Lumina/Sets/Web/react.production.min.js"),
            ("design/handoff/vendor/react-dom.production.min.js", "Lumina/Sets/Web/react-dom.production.min.js"),
            ("design/handoff/vendor/babel.min.js", "Lumina/Sets/Web/babel.min.js"),
        ]
        for (design, bundled) in pairs {
            let a = try Data(contentsOf: repo.appendingPathComponent(design))
            let b = try Data(contentsOf: repo.appendingPathComponent(bundled))
            XCTAssertEqual(SHA256.hash(data: a).description, SHA256.hash(data: b).description,
                           "\(bundled) drifted from \(design) — run Scripts/sets_sync_ui.sh")
        }
    }

    func testVendoredRuntimeMatchesTheSRIPinnedInSupportJS() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let support = try String(contentsOf: repo.appendingPathComponent("design/handoff/lumina-cull/support.js"), encoding: .utf8)
        for (file, key) in [("react.production.min.js", "REACT_SRI"), ("react-dom.production.min.js", "REACT_DOM_SRI"), ("babel.min.js", "BABEL_SRI")] {
            let data = try Data(contentsOf: repo.appendingPathComponent("design/handoff/vendor/\(file)"))
            let sri = "sha384-" + Data(SHA384.hash(data: data)).base64EncodedString()
            XCTAssertTrue(support.contains("var \(key) = \"\(sri)\""), "\(file) doesn't match \(key) in support.js")
        }
    }
}
