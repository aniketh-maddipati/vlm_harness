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

    // MARK: Temp names (Q4-F4)

    /// A temp name is 37 bytes whatever the file is called, carries the file's tag, and only that
    /// exact form is recognised as Lumina's.
    func testTempNamesHaveAFixedLengthAndATag() {
        for name in ["a", "DSC00001.xmp", String(repeating: "L", count: 251) + ".xmp", "📷 ceremony 🔥.ARW", "line\nbreak.xmp"] {
            let t = SetsFileOps.tempName(for: name)
            XCTAssertEqual(t.utf8.count, 37, name)
            XCTAssertTrue(t.hasPrefix(".lumina-tmp-"), "hidden, and found by the same '.lumina-tmp-' the probe and the tests look for")
            XCTAssertEqual(SetsFileOps.tempTag(of: t), SetsFileOps.tempTag(for: name))
            XCTAssertNotEqual(t, SetsFileOps.tempName(for: name), "two writes of one file never share a temp file")
        }
        XCTAssertNotEqual(SetsFileOps.tempTag(for: "DSC00001.xmp"), SetsFileOps.tempTag(for: "DSC00002.xmp"))
        let tag = SetsFileOps.tempTag(for: "DSC00001.xmp")
        for other in ["lumina-tmp-\(tag)-1234ABCD", ".lumina-tmp-\(tag)-1234ABCD.txt", ".lumina-tmp-\(tag)-1234ABC", ".lumina-tmp-\(tag)", ".lumina-tmp-\(tag)-1234ABCD-2",
                      ".lumina-tmp-\(tag.uppercased())-1234ABCD", ".lumina-tmp-\(tag.dropLast())g-1234ABCD", ".lumina-tmp-\(tag)-1234ABCG", ".lumina-tmp-notes", ".DSC00001.xmp.lumina-tmp-1234abcd", ""] {
            XCTAssertNil(SetsFileOps.tempTag(of: other), other)
        }
    }

    /// Files whose names fill the 255 bytes a name may have: written, replaced-with-backup refused
    /// by name ("name too long"), copied, and nothing left behind.
    func testNamesOf255BytesAreWrittenAndCopied() throws {
        let long = String(repeating: "L", count: 251)
        let url = dir.appendingPathComponent(long + ".xmp")
        XCTAssertFalse(try SetsFileOps.write(Data("one".utf8), to: url).backedUp)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "one")
        XCTAssertThrowsError(try SetsFileOps.write(Data("two".utf8), to: url)) { e in
            XCTAssertEqual(SetsFileOps.reason(e), SetsFileOps.nameTooLong, "\(e)")
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "one", "never replaced without a backup")
        let src = dir.appendingPathComponent("src/" + long + ".ARW"), dst = dir.appendingPathComponent("out/" + long + ".ARW")
        try FileManager.default.createDirectory(at: src.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("raw bytes".utf8).write(to: src)
        XCTAssertEqual(try SetsFileOps.copyVerified(src, to: dst), .copied(dst))
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "raw bytes")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("out").path), [long + ".ARW"])
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)), ["src", "out", long + ".xmp"])
    }

    /// Kill -9 mid-write leaves `.lumina-tmp-<tag>-<8 hex>`. The next launch removes the ones whose
    /// tag is a planned file's (or its backup's, or a numbered copy's: it keeps the planned name's
    /// tag), in the planned folders, and nothing else: not another file's temp, not a name that
    /// only looks like one. An older Lumina's `.<name>.lumina-tmp-*` is still recognised.
    func testRecoveryRecognisesItsOwnTempNames() throws {
        let fm = FileManager.default
        let dest = dir.appendingPathComponent("export"), jdir = dir.appendingPathComponent("journal")
        try fm.createDirectory(at: dest.appendingPathComponent("RAW"), withIntermediateDirectories: true)
        let long = String(repeating: "L", count: 251) + ".xmp"
        let journal = SetsExportJournal(directory: jdir)
        journal.begin(label: "both", destination: dest, names: ["DSC00001.xmp", long, "RAW/DSC00001.ARW"])
        let tmp = { (name: String, rnd: String) in ".lumina-tmp-\(SetsFileOps.tempTag(for: name))-\(rnd)" }
        let ours = [tmp("DSC00001.xmp", "1234ABCD"), tmp("DSC00001.xmp.lumina-bak", "5678ABCD"), tmp(long, "0A0A0A0A"), "RAW/" + tmp("DSC00001.ARW", "9ABCDEF0"),
                    "RAW/" + tmp("DSC00001.ARW", "0FEDCBA9"), ".DSC00001.xmp.lumina-tmp-1234abcd", "RAW/.DSC00001-2.ARW.lumina-tmp-0fedcba9"]
        let theirs = ["DSC00001.xmp", tmp("DSC00002.xmp", "1234ABCD"), tmp("DSC00001.xmp", "1234ABCD") + ".txt", ".lumina-tmp-notes", "lumina-tmp-" + SetsFileOps.tempTag(for: "DSC00001.xmp") + "-1234ABCD",
                      ".DSC00002.xmp.lumina-tmp-1234abcd", "RAW/.hidden"]
        for f in ours + theirs { try Data("x".utf8).write(to: dest.appendingPathComponent(f)) }
        // Outside the planned folders nothing is looked at, whatever its name.
        try fm.createDirectory(at: dest.appendingPathComponent("other"), withIntermediateDirectories: true)
        let elsewhere = dest.appendingPathComponent("other/" + tmp("DSC00001.xmp", "1234ABCD"))
        try Data("x".utf8).write(to: elsewhere)
        // A journal write cut short leaves its own temp file beside the journals.
        let journalTemp = jdir.appendingPathComponent(tmp("export-1.json", "1234ABCD"))
        try Data("x".utf8).write(to: journalTemp)
        let rec = SetsExportJournal.recover(in: jdir)
        XCTAssertEqual(rec.first?.tempsRemoved, ours.count)
        for f in ours { XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent(f).path), f) }
        for f in theirs { XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent(f).path), "must not touch \(f)") }
        XCTAssertTrue(fm.fileExists(atPath: elsewhere.path))
        XCTAssertFalse(fm.fileExists(atPath: journalTemp.path))
        XCTAssertEqual(SetsExportJournal.unfinished(in: jdir).count, 1, "the journal itself is kept")
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
