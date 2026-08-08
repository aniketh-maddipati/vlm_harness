import XCTest
@testable import Lumina

/// Leader-render contract for in-editor neighbor navigation.
@MainActor
final class P0InspectNavigationTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("p0-inspect-nav-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testInspectNeighborNavStartsLeaderRenderImmediately() throws {
        let a = UUID()
        let b = UUID()
        let pathA = tempDir.appendingPathComponent("a.jpg")
        let pathB = tempDir.appendingPathComponent("b.jpg")
        FileManager.default.createFile(atPath: pathA.path, contents: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        FileManager.default.createFile(atPath: pathB.path, contents: Data([0xFF, 0xD8, 0xFF, 0xD9]))

        let session = P0SessionModel()
        session.assets = [
            makeAsset(id: a, path: pathA.path),
            makeAsset(id: b, path: pathB.path),
        ]
        session.inspectingAssetID = a
        session.focusedAssetID = a
        session.setFocus(b)

        XCTAssertEqual(session.inspectingAssetID, b)
        XCTAssertEqual(
            session.developScheduler.fidelityByPhoto[b],
            .settling,
            "leader openRender must run synchronously on neighbor nav, not after debounce"
        )
    }

    private func makeAsset(id: UUID, path: String) -> AssetRecord {
        AssetRecord(
            id: id,
            sourceKey: "test-\(id.uuidString)",
            source: SourceReference(
                originalPath: path,
                relativePath: URL(fileURLWithPath: path).lastPathComponent,
                availability: .available
            ),
            filename: URL(fileURLWithPath: path).lastPathComponent,
            thumbPath: path,
            proxyPath: path
        )
    }
}
