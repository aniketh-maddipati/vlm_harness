import CryptoKit
import XCTest
@testable import Lumina

/// The app ships the design's page unchanged (BUILD-exact rule 1). The bundled copies in
/// Lumina/Sets/Web must be byte-identical to design/handoff; run Scripts/sets_sync_ui.sh after a
/// new handoff.
final class SetsPageBytesTests: XCTestCase {
    func testBundledPageMatchesTheDesign() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let pairs: [(String, String)] = [
            // Same list as Scripts/page_files.sh
            ("design/handoff/lumina-cull/Lumina Sets v11.dc.html", "Lumina/Sets/Web/Lumina Sets v11.dc.html"),
            ("design/handoff/lumina-cull/Lumina Edit v22.dc.html", "Lumina/Sets/Web/Lumina Edit v22.dc.html"),
            ("design/handoff/lumina-cull/support.js", "Lumina/Sets/Web/support.js"),
            ("design/handoff/lumina-cull/lumina-core-v4.js", "Lumina/Sets/Web/lumina-core-v4.js"),
            ("design/handoff/lumina-cull/lumina-v4-data.js", "Lumina/Sets/Web/lumina-v4-data.js"),
            ("design/handoff/lumina-cull/lumina-measure.js", "Lumina/Sets/Web/lumina-measure.js"),
            ("design/handoff/lumina-cull/lumina-selftest.js", "Lumina/Sets/Web/lumina-selftest.js"),
            ("design/handoff/vendor/react.production.min.js", "Lumina/Sets/Web/react.production.min.js"),
            ("design/handoff/vendor/react-dom.production.min.js", "Lumina/Sets/Web/react-dom.production.min.js"),
        ]
        for (design, bundled) in pairs {
            let a = try Data(contentsOf: repo.appendingPathComponent(design))
            let b = try Data(contentsOf: repo.appendingPathComponent(bundled))
            XCTAssertEqual(SHA256.hash(data: a).description, SHA256.hash(data: b).description,
                           "\(bundled) drifted from \(design) — run Scripts/sets_sync_ui.sh")
        }
    }

    /// Babel stays in design/handoff/vendor (the prototype) but not in the app: no page file loads it.
    func testBabelIsNotBundled() {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent("Lumina/Sets/Web/babel.min.js").path),
                       "babel.min.js is back in Lumina/Sets/Web — run Scripts/sets_sync_ui.sh")
        XCTAssertFalse(SetsSchemeHandler.vendorFiles.contains("babel.min.js"))
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
