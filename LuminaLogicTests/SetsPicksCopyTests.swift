import XCTest
@testable import Lumina

/// DNG picks use the same verified-copy path as RAW exports, but land one folder below the
/// destination. These tests hold the copy-only trust rules without using real photos.
final class SetsPicksCopyTests: XCTestCase {
    private let fm = FileManager.default
    private var dir: URL!

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sets-picks-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
    }

    private func bytes(_ seed: UInt8, count: Int = 4096) -> Data {
        Data((0..<count).map { seed &+ UInt8($0 % 197) })
    }

    private func tempFiles(in root: URL) -> [String] {
        ((fm.enumerator(atPath: root.path)?.allObjects as? [String]) ?? [])
            .filter { $0.contains(".lumina-tmp-") }
    }

    func testDNGPicksAndSidecarsLandVerifiedWithoutChangingSources() throws {
        let source = dir.appendingPathComponent("source"), destination = dir.appendingPathComponent("export")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let dngs = try (1...3).map { i -> URL in
            let url = source.appendingPathComponent("IMG_000\(i).DNG")
            try bytes(UInt8(i)).write(to: url)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            return url
        }
        let before = try dngs.map {
            (try SetsFileOps.sha256(file: $0), try XCTUnwrap(fm.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date))
        }
        let items = dngs.map { SetsExportJob.Item.copy(name: "Picks/\($0.lastPathComponent)", source: $0) } + [
            .bytes(name: "IMG_0001.xmp", data: Data("one".utf8)),
            .bytes(name: "IMG_0002.xmp", data: Data("two".utf8))
        ]
        let job = SetsExportJob(label: "picks", destination: destination, items: items)

        let first = job.run(journal: nil, sources: [source])
        XCTAssertEqual(first.n, 5)
        XCTAssertEqual(first.errors, [])
        XCTAssertEqual(first.renamed, 0)
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent("Picks").path))
        for (i, sourceURL) in dngs.enumerated() {
            let copy = destination.appendingPathComponent("Picks/\(sourceURL.lastPathComponent)")
            XCTAssertEqual(try SetsFileOps.sha256(file: copy), before[i].0)
            XCTAssertEqual(try SetsFileOps.sha256(file: sourceURL), before[i].0)
            XCTAssertEqual(try XCTUnwrap(fm.attributesOfItem(atPath: sourceURL.path)[.modificationDate] as? Date), before[i].1)
        }
        XCTAssertEqual(tempFiles(in: destination), [])

        let second = job.run(journal: nil, sources: [source])
        XCTAssertEqual(second.n, 5)
        XCTAssertEqual(second.errors, [])
        XCTAssertEqual(second.renamed, 0)
        XCTAssertFalse(fm.fileExists(atPath: destination.appendingPathComponent("Picks/IMG_0001-2.DNG").path))
        XCTAssertEqual(tempFiles(in: destination), [])
    }

    func testDifferentExistingPickGetsANumberedCopy() throws {
        let source = dir.appendingPathComponent("source/X.DNG")
        let destination = dir.appendingPathComponent("export")
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: destination.appendingPathComponent("Picks"), withIntermediateDirectories: true)
        try Data("new".utf8).write(to: source)
        let old = destination.appendingPathComponent("Picks/X.DNG")
        try Data("old".utf8).write(to: old)

        let result = SetsExportJob(label: "picks", destination: destination,
                                   items: [.copy(name: "Picks/X.DNG", source: source)]).run(journal: nil)

        XCTAssertEqual(result.n, 1)
        XCTAssertEqual(result.renamed, 1)
        XCTAssertEqual(try Data(contentsOf: old), Data("old".utf8))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Picks/X-2.DNG")), Data("new".utf8))
        XCTAssertTrue(fm.fileExists(atPath: source.path))
        XCTAssertEqual(tempFiles(in: destination), [])
    }

    func testMissingSourceIsReportedAndOtherItemsStillLand() throws {
        let source = dir.appendingPathComponent("source")
        let destination = dir.appendingPathComponent("export")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let present = source.appendingPathComponent("A.DNG")
        let missing = source.appendingPathComponent("B.DNG")
        try Data("a".utf8).write(to: present)
        try Data("b".utf8).write(to: missing)
        let job = SetsExportJob(label: "picks", destination: destination, items: [
            .copy(name: "Picks/B.DNG", source: missing),
            .copy(name: "Picks/A.DNG", source: present),
            .bytes(name: "A.xmp", data: Data("xmp".utf8))
        ])
        try fm.removeItem(at: missing)

        let result = job.run(journal: nil, sources: [source])

        XCTAssertEqual(result.n, 2)
        XCTAssertEqual(result.errors, [.init(name: "Picks/B.DNG", reason: "missing")])
        XCTAssertEqual(result.failed.count, 1)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Picks/A.DNG")), Data("a".utf8))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("A.xmp")), Data("xmp".utf8))
        XCTAssertFalse(fm.fileExists(atPath: destination.appendingPathComponent("Picks/B.DNG").path))
        XCTAssertEqual(tempFiles(in: destination), [])
    }

    func testNamesOutsideOneSubfolderAreRefused() throws {
        let destination = dir.appendingPathComponent("export")
        let items: [SetsExportJob.Item] = [
            .bytes(name: "../x.dng", data: Data("1".utf8)),
            .bytes(name: "/abs/x.dng", data: Data("2".utf8)),
            .bytes(name: "Picks/../../x.dng", data: Data("3".utf8))
        ]

        let result = SetsExportJob(label: "picks", destination: destination, items: items).run(journal: nil)

        XCTAssertEqual(result.n, 0)
        XCTAssertEqual(result.errors.map(\.name), items.map(\.name))
        XCTAssertTrue(result.errors.allSatisfy { $0.reason == "outside the export folder" })
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("x.dng").path))
    }

    func testLinkedPicksFolderOutsideDestinationIsRefused() throws {
        let source = dir.appendingPathComponent("source"), destination = dir.appendingPathComponent("export")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: destination.appendingPathComponent("Picks"), withDestinationURL: source)
        let original = source.appendingPathComponent("original.DNG")
        try Data("raw".utf8).write(to: original)

        let result = SetsExportJob(label: "picks", destination: destination,
                                   items: [.copy(name: "Picks/copy.DNG", source: original)])
            .run(journal: nil, sources: [source])

        XCTAssertEqual(result.n, 0)
        XCTAssertEqual(result.errors.first?.name, "Picks/copy.DNG")
        XCTAssertFalse(fm.fileExists(atPath: source.appendingPathComponent("copy.DNG").path))
    }

    func testOldResultWithoutErrorsDecodes() throws {
        let json = Data(#"{"n":2,"bak":1,"renamed":0,"folder":"/tmp/out","failed":[],"decoders":[],"fallbacks":[],"renderMs":[]}"#.utf8)
        let result = try JSONDecoder().decode(SetsExportJob.Result.self, from: json)
        XCTAssertEqual(result.n, 2)
        XCTAssertEqual(result.errors, [])
    }

    func testJournalKeepsNestedPlannedAndDoneNamesAcrossRecovery() throws {
        let destination = dir.appendingPathComponent("export"), journalDir = dir.appendingPathComponent("journals")
        try fm.createDirectory(at: destination.appendingPathComponent("Picks"), withIntermediateDirectories: true)
        let names = ["Picks/A.DNG", "Picks/B.DNG", "Picks/C.DNG"]
        let journal = SetsExportJournal(directory: journalDir)
        journal.begin(label: "picks", destination: destination, names: names)
        journal.done(names[0])

        XCTAssertEqual(SetsExportJournal.unfinished(in: journalDir).first?.planned, names)
        XCTAssertEqual(SetsExportJournal.unfinished(in: journalDir).first?.done, [names[0]])
        let recovered = SetsExportJournal.recover(in: journalDir)
        XCTAssertEqual(recovered.first?.planned, names)
        XCTAssertEqual(recovered.first?.done, [names[0]])
    }
}
