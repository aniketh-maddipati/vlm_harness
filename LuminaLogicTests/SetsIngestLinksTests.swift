import XCTest
@testable import Lumina

/// T6 (THREAT-MODEL.md): a symbolic link inside an opened folder must not lead a read out of it.
/// `resolve` is the gate for every native read (head, preview, thumbnail, the Edit render, the
/// canvas, export), so a nil from it covers them all. Every link below the root is refused, even one
/// that stays inside the shoot; the root itself may be reached through a link.
final class SetsIngestLinksTests: XCTestCase {
    private var dir: URL!
    private var root: URL!
    private var outside: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        // Under FileManager's temporary directory, itself behind the /var → /private/var link.
        dir = fm.temporaryDirectory.appendingPathComponent("sets-ingest-links-\(UUID().uuidString)", isDirectory: true)
        root = dir.appendingPathComponent("shoot", isDirectory: true)
        outside = dir.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("100MSDCF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try raw().write(to: outside.appendingPathComponent("SECRET.ARW"))
        try raw().write(to: root.appendingPathComponent("100MSDCF/DSC00001.ARW"))
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    /// 4 KB of bytes with a "preview" at 1000 … 3000 (returned as stored for orientation 1).
    private func raw() -> Data { Data((0..<4096).map { UInt8($0 % 251) }) }

    private func link(_ rel: String, to target: URL) throws {
        try fm.createSymbolicLink(at: root.appendingPathComponent(rel), withDestinationURL: target)
    }

    private func ingest() -> SetsIngest { let i = SetsIngest(workers: 1); i.register(root); return i }

    private func assertRefused(_ i: SetsIngest, _ rel: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(i.resolve(rel), "resolve: \(rel)", file: file, line: line)
        let p = SetsIngest.Preview(rel: rel, offset: 1000, length: 2000, orientation: 1)
        XCTAssertThrowsError(try i.head(rel), "head: \(rel)", file: file, line: line) { e in
            XCTAssertEqual((e as? SetsIngest.Failure)?.kind, .notFound, file: file, line: line)
        }
        XCTAssertThrowsError(try i.preview(p), "preview: \(rel)", file: file, line: line)
        XCTAssertThrowsError(try i.thumb(p), "thumb: \(rel)", file: file, line: line)
    }

    func testANormalFileStillReads() throws {
        let i = ingest(), rel = "shoot/100MSDCF/DSC00001.ARW"
        XCTAssertEqual(i.resolve(rel)?.lastPathComponent, "DSC00001.ARW")
        XCTAssertEqual(try i.head(rel), raw())
        XCTAssertEqual(try i.preview(.init(rel: rel, offset: 1000, length: 2000, orientation: 1)), raw().subdata(in: 1000..<3000))
    }

    func testALinkedFilePointingOutsideIsRefused() throws {
        try link("100MSDCF/DSC00002.ARW", to: outside.appendingPathComponent("SECRET.ARW"))
        let i = ingest()
        assertRefused(i, "shoot/100MSDCF/DSC00002.ARW")
        XCTAssertEqual(i.snapshot.bytesRead, 0)
    }

    func testALinkedFolderPointingOutsideIsRefused() throws {
        try link("101MSDCF", to: outside)
        let i = ingest()
        assertRefused(i, "shoot/101MSDCF/SECRET.ARW")
        // Not even a name that isn't there yet: the link is on the way.
        XCTAssertNil(i.resolve("shoot/101MSDCF/NOPE.ARW"))
        XCTAssertEqual(i.snapshot.bytesRead, 0)
    }

    func testALinkThatStaysInsideTheShootIsRefusedToo() throws {
        try link("100MSDCF/DSC00003.ARW", to: root.appendingPathComponent("100MSDCF/DSC00001.ARW"))
        try link("102MSDCF", to: root.appendingPathComponent("100MSDCF"))
        let i = ingest()
        assertRefused(i, "shoot/100MSDCF/DSC00003.ARW")
        assertRefused(i, "shoot/102MSDCF/DSC00001.ARW")
    }

    func testADanglingLinkIsRefused() throws {
        try link("100MSDCF/DSC00004.ARW", to: outside.appendingPathComponent("NOT-THERE.ARW"))
        assertRefused(ingest(), "shoot/100MSDCF/DSC00004.ARW")
    }

    func testDotDotThroughALinkedFolderStaysLexical() throws {
        // "101MSDCF/../" is collapsed by name before anything is opened, so it can't climb via the link's target.
        try link("101MSDCF", to: outside)
        let i = ingest()
        XCTAssertEqual(i.resolve("shoot/101MSDCF/../100MSDCF/DSC00001.ARW")?.lastPathComponent, "DSC00001.ARW")
        XCTAssertEqual(try i.head("shoot/101MSDCF/../100MSDCF/DSC00001.ARW"), raw())
        XCTAssertNil(i.resolve("shoot/101MSDCF/../../outside/SECRET.ARW"))
    }

    /// The folder the user chose may itself be reached through a link: only links below it are refused.
    func testARootReachedThroughALinkReads() throws {
        let alias = dir.appendingPathComponent("alias", isDirectory: true)
        try fm.createSymbolicLink(at: alias, withDestinationURL: root)
        let i = SetsIngest(workers: 1)
        i.register(alias)
        XCTAssertEqual(try i.head("alias/100MSDCF/DSC00001.ARW"), raw())
    }

    /// The card-gone behaviour is unchanged: a root that disappears reports gone, not not-found.
    func testAFileUnderARootThatDisappearedIsGone() throws {
        let i = ingest(), rel = "shoot/100MSDCF/DSC00001.ARW"
        try fm.removeItem(at: root)
        XCTAssertNotNil(i.resolve(rel), "still resolves, so a caller can say what happened")
        XCTAssertThrowsError(try i.head(rel)) { e in XCTAssertEqual((e as? SetsIngest.Failure)?.kind, .gone) }
        XCTAssertEqual(i.snapshot.gone, ["shoot"])
    }

    /// A root registered before its folder exists (a card not in yet) reads once it appears.
    func testARootThatAppearsAfterRegisterReads() throws {
        let later = dir.appendingPathComponent("later", isDirectory: true)
        let i = SetsIngest(workers: 1)
        i.register(later)
        XCTAssertNotNil(i.resolve("later/100MSDCF/DSC00001.ARW"))
        try fm.createDirectory(at: later.appendingPathComponent("100MSDCF"), withIntermediateDirectories: true)
        try raw().write(to: later.appendingPathComponent("100MSDCF/DSC00001.ARW"))
        XCTAssertEqual(try i.head("later/100MSDCF/DSC00001.ARW"), raw())
        try fm.createSymbolicLink(at: later.appendingPathComponent("100MSDCF/DSC00002.ARW"), withDestinationURL: outside.appendingPathComponent("SECRET.ARW"))
        XCTAssertNil(i.resolve("later/100MSDCF/DSC00002.ARW"))
    }
}
