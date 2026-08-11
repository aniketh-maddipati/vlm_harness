import XCTest
@testable import Lumina

@MainActor
final class AssetIdentityTests: XCTestCase {

    func testStableAssetIdentityAfterRediscovery() {
        let key = AssetIdentity.sourceKey(
            volumeID: "VOL-A",
            relativePath: "nested/DSC0001.ARW",
            fileSize: 42_000_000,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let id1 = AssetIdentity.resolveID(sourceKey: key)
        let id2 = AssetIdentity.resolveID(sourceKey: key)
        XCTAssertEqual(id1, id2)
    }

    func testPreservedLegacyIDWinsOnMigration() {
        let key = AssetIdentity.sourceKey(
            volumeID: "VOL-A",
            relativePath: "nested/DSC0001.ARW",
            fileSize: 42_000_000,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let preserved = UUID()
        XCTAssertEqual(AssetIdentity.resolveID(sourceKey: key, preserved: preserved), preserved)
    }

    func testSameFilenameDifferentPathsStayDistinct() {
        let a = AssetIdentity.sourceKey(volumeID: "VOL", relativePath: "a/DSC0001.ARW", fileSize: 10, capturedAt: nil)
        let b = AssetIdentity.sourceKey(volumeID: "VOL", relativePath: "b/DSC0001.ARW", fileSize: 10, capturedAt: nil)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(AssetIdentity.resolveID(sourceKey: a), AssetIdentity.resolveID(sourceKey: b))
    }

    func testCacheStemKeyedByAssetIdentity() {
        let id = UUID()
        XCTAssertEqual(AssetIdentity.cacheStem(for: id), id.uuidString.lowercased())
        XCTAssertFalse(AssetIdentity.cacheStem(for: id).contains("DSC"))
    }

    func testRelativePathDistinctForNestedDuplicates() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lumina-id-\(UUID().uuidString)", isDirectory: true)
        let nestedA = root.appendingPathComponent("a", isDirectory: true)
        let nestedB = root.appendingPathComponent("b", isDirectory: true)
        try fm.createDirectory(at: nestedA, withIntermediateDirectories: true)
        try fm.createDirectory(at: nestedB, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let fileA = nestedA.appendingPathComponent("DSC0001.ARW")
        let fileB = nestedB.appendingPathComponent("DSC0001.ARW")
        try Data([0x01]).write(to: fileA)
        try Data([0x02]).write(to: fileB)

        let relA = AssetIdentity.relativePath(file: fileA, root: root)
        let relB = AssetIdentity.relativePath(file: fileB, root: root)
        XCTAssertNotEqual(relA, relB)
    }
}
