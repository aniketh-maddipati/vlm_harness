import XCTest
@testable import Lumina

final class BuildManifestTests: XCTestCase {

    func testEmbeddedManifestLoadsInAppBundle() {
        guard let manifest = LuminaBuildManifest.load() else {
            XCTFail("LuminaBuildManifest.json missing from app bundle — run write_build_manifest.py / build")
            return
        }
        XCTAssertFalse(manifest.gitSha.isEmpty)
        XCTAssertFalse(manifest.tokensHash.isEmpty)
        XCTAssertFalse(manifest.fixtureManifestVersion.isEmpty)
        XCTAssertFalse(manifest.contractVersion.isEmpty)
        XCTAssertFalse(manifest.buildDate.isEmpty)
    }

    func testA7SocketInactiveInWaveBuild() {
        XCTAssertNil(BetaDiagnosticsSocket.activeKind)
    }

    func testBugReportLineIncludesShaAndTokens() {
        guard let manifest = LuminaBuildManifest.load() else { return }
        let line = manifest.bugReportLine
        XCTAssertTrue(line.contains(manifest.marketingVersion))
        XCTAssertTrue(line.contains("tokens="))
    }
}
