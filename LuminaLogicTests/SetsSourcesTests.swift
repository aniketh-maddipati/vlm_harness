import XCTest
@testable import Lumina

/// Shoot sources are ordered bookmark grants. Fakes verify that status and reconnect never turn
/// the last-known display path into an authority; the final test exercises a real bookmark move.
final class SetsSourcesTests: XCTestCase {
    private final class Fake {
        var locations: [Data: URL] = [:]
        var stale: Set<Data> = []
        var refused: Set<Data> = []
        var bookmarkCount = 0
        var existsCalls: [URL] = []

        func calls() -> SetsAccess.Calls {
            SetsAccess.Calls(
                start: { _ in false },
                stop: { _ in },
                resolve: { [unowned self] data in
                    if refused.contains(data) { throw CocoaError(.fileNoSuchFile) }
                    guard let url = locations[data] else { throw CocoaError(.fileReadCorruptFile) }
                    return (url, stale.contains(data))
                },
                bookmark: { [unowned self] url in
                    bookmarkCount += 1
                    let data = Data("bookmark-\(bookmarkCount)".utf8)
                    locations[data] = url
                    return data
                },
                exists: { [unowned self] url in
                    existsCalls.append(url)
                    var directory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
                })
        }
    }

    private let fm = FileManager.default
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = fm.temporaryDirectory.appendingPathComponent("sets-sources-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    private func folder(_ name: String) throws -> URL {
        let url = sandbox.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testAddsTwoFoldersInOrder() throws {
        let fake = Fake()
        let date = Date(timeIntervalSince1970: 1_234)
        var sources = SetsSources(calls: fake.calls(), now: { date })
        let first = try sources.add(url: folder("First"), kind: "folder", label: "First folder")
        let second = try sources.add(url: folder("Second"), kind: "card", label: "Camera card")

        XCTAssertEqual(sources.sources.map(\.id), [first.id, second.id])
        XCTAssertEqual(sources.sources.map(\.kind), ["folder", "card"])
        XCTAssertEqual(sources.sources.map(\.label), ["First folder", "Camera card"])
        XCTAssertEqual(sources.sources.map(\.added), [date, date])
    }

    func testAddingSameFolderAndSymlinkReturnsExistingSource() throws {
        let fake = Fake()
        var sources = SetsSources(calls: fake.calls())
        let folder = try folder("Shoot")
        let link = sandbox.appendingPathComponent("Shoot link", isDirectory: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: folder)

        let first = try sources.add(url: folder, kind: "folder", label: "Shoot")
        let same = try sources.add(url: folder, kind: "drop", label: "Again")
        let linked = try sources.add(url: link, kind: "drop", label: "Link")

        XCTAssertEqual(same, first)
        XCTAssertEqual(linked, first)
        XCTAssertEqual(sources.sources, [first])
        XCTAssertEqual(fake.bookmarkCount, 1, "duplicates do not create another grant")
    }

    func testCodableRoundTripPreservesOrderedSources() throws {
        let fake = Fake()
        var sources = SetsSources(calls: fake.calls(), now: { Date(timeIntervalSince1970: 99) })
        _ = try sources.add(url: folder("A"), kind: "pictures", label: "Pictures")
        _ = try sources.add(url: folder("B"), kind: "downloads", label: "Downloads")

        let decoded = try JSONDecoder().decode(SetsSources.self, from: JSONEncoder().encode(sources))

        XCTAssertEqual(decoded.sources, sources.sources)
    }

    func testDeletedFolderIsMissing() throws {
        let fake = Fake()
        var sources = SetsSources(calls: fake.calls())
        let gone = try folder("Gone")
        let source = try sources.add(url: gone, kind: "folder", label: "Gone")
        try fm.removeItem(at: gone)

        let status = try XCTUnwrap(sources.status().first)
        XCTAssertEqual(status.id, source.id)
        XCTAssertTrue(status.missing)
    }

    func testBookmarkFailureIsMissingWithoutReadingStoredPath() throws {
        let fake = Fake()
        var sources = SetsSources(calls: fake.calls())
        let source = try sources.add(url: folder("Still here"), kind: "folder", label: "Still here")
        fake.refused.insert(source.bookmark)
        fake.existsCalls = []

        let status = try XCTUnwrap(sources.status().first)
        XCTAssertTrue(status.missing)
        XCTAssertTrue(fake.existsCalls.isEmpty, "a failed bookmark must not fall back to Source.path")
    }

    func testReconnectRenewsStaleBookmarkWithoutChangingIdentity() throws {
        let fake = Fake()
        var sources = SetsSources(calls: fake.calls())
        let folder = try folder("Moved")
        let source = try sources.add(url: folder, kind: "folder", label: "Moved")
        fake.stale.insert(source.bookmark)

        XCTAssertEqual(sources.reconnect(source.id)?.path, folder.path)

        let renewed = try XCTUnwrap(sources.sources.first)
        XCTAssertEqual(renewed.id, source.id)
        XCTAssertNotEqual(renewed.bookmark, source.bookmark)
        XCTAssertEqual(fake.bookmarkCount, 2)
        XCTAssertFalse(sources.status()[0].missing)
    }

    func testRelocateReplacesBookmarkAndPathWithoutChangingIdentity() throws {
        let fake = Fake()
        var sources = SetsSources(calls: fake.calls())
        let old = try folder("Old")
        let source = try sources.add(url: old, kind: "folder", label: "Shoot")
        try fm.removeItem(at: old)
        XCTAssertTrue(sources.status()[0].missing)
        let replacement = try folder("Replacement")

        let relocated = try XCTUnwrap(sources.relocate(source.id, to: replacement))

        XCTAssertEqual(relocated.id, source.id)
        XCTAssertEqual(relocated.path, replacement.path)
        XCTAssertNotEqual(relocated.bookmark, source.bookmark)
        XCTAssertFalse(sources.status()[0].missing)
    }

    func testRemoveAndReAddMakesANewIdentity() throws {
        let fake = Fake()
        var sources = SetsSources(calls: fake.calls())
        let folder = try folder("Shoot")
        let first = try sources.add(url: folder, kind: "folder", label: "Shoot")

        sources.remove(first.id)
        XCTAssertTrue(sources.sources.isEmpty)
        let second = try sources.add(url: folder, kind: "folder", label: "Shoot")

        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(sources.sources, [second])
    }

    func testRealBookmarkFollowsRenamedFolder() throws {
        let original = try folder("Real")
        var sources = SetsSources(calls: .system)
        let source: SetsSources.Source
        do {
            source = try sources.add(url: original, kind: "folder", label: "Real")
        } catch {
            throw XCTSkip("security-scoped bookmarks unavailable here: \(error)")
        }
        let renamed = sandbox.appendingPathComponent("Real renamed", isDirectory: true)
        try fm.moveItem(at: original, to: renamed)

        let resolved = try XCTUnwrap(sources.reconnect(source.id), "the bookmark follows a rename on the same volume")

        XCTAssertEqual(resolved.resolvingSymlinksInPath().path, renamed.path)
        XCTAssertEqual(sources.sources[0].id, source.id)
        XCTAssertFalse(sources.status()[0].missing)
    }
}
