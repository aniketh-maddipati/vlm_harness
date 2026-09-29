import CoreImage
import XCTest
@testable import Lumina

/// Trust rules for every file Lumina writes (ROADMAP trust list, README export contract), and the
/// Edit-look maths the RAW export shares with the page.
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

    // MARK: Edit look — the string LuminaCore.editFilter returns is the contract

    func testParsesEditFilterOutput() throws {
        XCTAssertEqual(try SetsEditLook.parse("none"), [])
        XCTAssertEqual(try SetsEditLook.parse("brightness(1.123) contrast(0.970) sepia(0.150)"),
                       [.brightness(1.123), .contrast(0.970), .sepia(0.150)])
        XCTAssertEqual(try SetsEditLook.parse("brightness(1.000) contrast(1.000) hue-rotate(-5.4deg)"),
                       [.brightness(1), .contrast(1), .hueRotate(degrees: -5.4)])
        XCTAssertThrowsError(try SetsEditLook.parse("drop-shadow(1px 1px red)"))
    }

    func testMatricesFollowTheFilterEffectsSpec() {
        // contrast(c): slope c, intercept 0.5 − 0.5c; hue-rotate(0) and sepia(0) are identity.
        let c = SetsEditLook.matrix(.contrast(1.2))!
        XCTAssertEqual(c.bias, -0.1, accuracy: 1e-12)
        for (op, expect) in [(SetsEditLook.Op.hueRotate(degrees: 0), [1.0, 0, 0, 0, 1, 0, 0, 0, 1]),
                             (.sepia(0), [1.0, 0, 0, 0, 1, 0, 0, 0, 1])] {
            let m = SetsEditLook.matrix(op)!.m
            for (a, b) in zip(m, expect) { XCTAssertEqual(a, b, accuracy: 1e-3) }
        }
    }

    func testBrightnessDoublesAMidGreyInSRGBValues() throws {
        let grey = CIImage(color: CIColor(red: 0.25, green: 0.25, blue: 0.25, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let out = SetsEditLook.apply([.brightness(2)], to: grey)
        var px = [Float](repeating: 0, count: 4)
        SetsEditLook.context.render(out, toBitmap: &px, rowBytes: 16, bounds: out.extent, format: .RGBAf,
                                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        XCTAssertEqual(Double(px[0]), 0.5, accuracy: 0.004)
    }
}
