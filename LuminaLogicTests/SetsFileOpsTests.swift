import XCTest
@testable import Lumina

/// Trust rules for every file Lumina writes (ROADMAP trust list, README export contract).
final class SetsFileOpsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sets-fileops-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testNewFileHasNoBackup() throws {
        let url = dir.appendingPathComponent("a/DSC00001.xmp")
        let r = try SetsFileOps.write(Data("one".utf8), to: url)
        XCTAssertFalse(r.backedUp)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "one")
        XCTAssertFalse(FileManager.default.fileExists(atPath: SetsFileOps.backupURL(for: url).path))
    }

    func testReplacingKeepsTheOldBytesAsLuminaBak() throws {
        let url = dir.appendingPathComponent("DSC00001.XMP")
        try Data("lightroom".utf8).write(to: url)
        let r = try SetsFileOps.write(Data("lumina".utf8), to: url)
        XCTAssertTrue(r.backedUp)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "lumina")
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("DSC00001.XMP.lumina-bak"), encoding: .utf8), "lightroom")
    }

    func testIdenticalBytesAreNotRewrittenOrBackedUp() throws {
        let url = dir.appendingPathComponent("same.xmp")
        try Data("x".utf8).write(to: url)
        XCTAssertFalse(try SetsFileOps.write(Data("x".utf8), to: url).backedUp)
        XCTAssertFalse(FileManager.default.fileExists(atPath: SetsFileOps.backupURL(for: url).path))
    }

    func testNoTempFilesLeftBehind() throws {
        let url = dir.appendingPathComponent("t.xmp")
        try SetsFileOps.write(Data("1".utf8), to: url)
        try SetsFileOps.write(Data("2".utf8), to: url)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(Set(names), ["t.xmp", "t.xmp.lumina-bak"])
    }

    func testCopyNeverOverwritesADifferentFile() throws {
        let a = dir.appendingPathComponent("src1/DSC00001.ARW"), b = dir.appendingPathComponent("src2/DSC00001.ARW")
        for (u, s) in [(a, "first card"), (b, "second card")] {
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(s.utf8).write(to: u)
        }
        let dst = dir.appendingPathComponent("out/DSC00001.ARW")
        XCTAssertEqual(try SetsFileOps.copyVerified(a, to: dst), .copied(dst))
        let second = try SetsFileOps.copyVerified(b, to: dst)
        let renamed = dir.appendingPathComponent("out/DSC00001-2.ARW")
        XCTAssertEqual(second, .renamed(renamed))
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "first card")
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "second card")
        XCTAssertEqual(try SetsFileOps.copyVerified(a, to: dst), .alreadyThere(dst))     // re-send: nothing new
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))                  // copy, never move
    }

    func testDestinationInsideSourceIsRefused() throws {
        let src = dir.appendingPathComponent("shoot")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        XCTAssertNotNil(SetsFileOps.refusal(destination: src, sources: [src]))
        XCTAssertNotNil(SetsFileOps.refusal(destination: src.appendingPathComponent("export"), sources: [src]))
        XCTAssertNil(SetsFileOps.refusal(destination: dir.appendingPathComponent("elsewhere"), sources: [src]))
    }
}
