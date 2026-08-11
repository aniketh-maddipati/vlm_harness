import XCTest
@testable import Lumina

@MainActor
final class ContactSheetTests: XCTestCase {

    func testRecursiveDiscoveryAndSkipAccounting() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("p0-cs-\(UUID().uuidString)", isDirectory: true)
        let nestedA = root.appendingPathComponent("a", isDirectory: true)
        let nestedB = root.appendingPathComponent("b", isDirectory: true)
        try fm.createDirectory(at: nestedA, withIntermediateDirectories: true)
        try fm.createDirectory(at: nestedB, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try Data([0x01, 0x02, 0x03, 0x04]).write(to: nestedA.appendingPathComponent("DSC0001.ARW"))
        try Data([0x05, 0x06, 0x07, 0x08]).write(to: nestedB.appendingPathComponent("DSC0001.ARW"))
        try Data([0x11]).write(to: nestedA.appendingPathComponent("DSC0002.JPG"))
        try Data([0x22]).write(to: nestedA.appendingPathComponent("notes.txt"))
        try Data([0x33]).write(to: nestedA.appendingPathComponent("clip.MOV"))
        try Data([0x44]).write(to: nestedA.appendingPathComponent("sidecar.XMP"))

        let discovery = MediaFormats.discoverPhotos(at: root)
        XCTAssertEqual(discovery.importable.count, 3)
        XCTAssertTrue(discovery.skipped.contains(where: { $0.reason == .unsupported }))
        XCTAssertTrue(discovery.skipped.contains(where: { $0.reason == .video }))
        XCTAssertTrue(discovery.skipped.contains(where: { $0.reason == .sidecar }))
    }

    func testDuplicateSuppressionOnRediscovery() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("p0-dup-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("DSC0001.JPG")
        try Data([0x01]).write(to: file)

        let discovery = MediaFormats.discoverPhotos(at: root)
        var seenKeys = Set<String>()
        var dupSkipped = 0
        for url in discovery.importable + discovery.importable {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let key = "\(url.path)|\(size)"
            if seenKeys.contains(key) {
                dupSkipped += 1
                continue
            }
            seenKeys.insert(key)
        }
        XCTAssertEqual(dupSkipped, discovery.importable.count)
    }

    func testWorkspaceRestoreRoundTrip() throws {
        let focus = UUID()
        var restore = WorkspaceRestoreState(
            focusedAssetID: focus,
            filter: .keeps,
            contactSheetDensity: 8,
            scrollAnchor: 0.42,
            scale: .contactSheet,
            keptOrderMode: false
        )
        let data = try JSONEncoder().encode(restore)
        let decoded = try JSONDecoder().decode(WorkspaceRestoreState.self, from: data)
        XCTAssertEqual(decoded.focusedAssetID, focus)
        XCTAssertEqual(decoded.filter, .keeps)
        XCTAssertEqual(decoded.contactSheetDensity, 8)
        XCTAssertEqual(decoded.scrollAnchor ?? -1, 0.42, accuracy: 0.0001)
    }

    func testLegacyCacheMigrationToIdentityKey() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("p0-cache-\(UUID().uuidString)", isDirectory: true)
        let cacheDir = root.appendingPathComponent("cache/grid512", isDirectory: true)
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let assetID = UUID()
        let legacyCache = cacheDir.appendingPathComponent("DSC0001.jpg")
        let identityCache = cacheDir.appendingPathComponent(AssetIdentity.cacheStem(for: assetID) + ".jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: legacyCache)
        AssetIdentity.migrateLegacyCache(from: legacyCache, to: identityCache)
        XCTAssertTrue(fm.fileExists(atPath: identityCache.path))
        XCTAssertEqual(identityCache.lastPathComponent, assetID.uuidString.lowercased() + ".jpg")
    }
}
