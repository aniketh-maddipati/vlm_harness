import XCTest
@testable import Lumina

final class SetsDuplicatesTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sets-duplicates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        var data = Data(count: count)
        data.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: .min ... .max, using: &generator)
            }
        }
        return data
    }

    private func put(_ name: String, bytes: Data) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    func testIdenticalCopiesAreSame() throws {
        let bytes = randomBytes(1 << 20)
        let a = try put("a.ARW", bytes: bytes)
        let b = try put("b.ARW", bytes: bytes)

        XCTAssertEqual(SetsDuplicates.confirm([.init(a: a, b: b)], isCancelled: { false }), [.same])
    }

    func testByteFlippedAtEndIsDifferent() throws {
        let aBytes = randomBytes(3 << 20)
        var bBytes = aBytes
        bBytes[bBytes.index(before: bBytes.endIndex)] ^= 0xff
        let a = try put("a.ARW", bytes: aBytes)
        let b = try put("b.ARW", bytes: bBytes)

        XCTAssertEqual(SetsDuplicates.confirm([.init(a: a, b: b)], isCancelled: { false }), [.different])
    }

    func testDifferentSizesAreNotHashed() throws {
        let a = try put("a.ARW", bytes: randomBytes(1 << 20))
        let b = try put("b.ARW", bytes: randomBytes((1 << 20) + 1))
        var hashes = 0
        let calls = SetsDuplicates.Calls(
            size: {
                let number = try FileManager.default.attributesOfItem(atPath: $0.path)[.size] as! NSNumber
                return number.int64Value
            },
            hash: { _, _ in hashes += 1; return "" })

        XCTAssertEqual(SetsDuplicates.confirm([.init(a: a, b: b)], isCancelled: { false }, calls: calls), [.different])
        XCTAssertEqual(hashes, 0)
    }

    func testMissingFileIsUnreadable() throws {
        let present = try put("present.ARW", bytes: randomBytes(1 << 20))
        let missing = dir.appendingPathComponent("missing.ARW")

        let answer = SetsDuplicates.confirm([.init(a: missing, b: present)], isCancelled: { false })
        guard case .unreadable = answer.first else {
            return XCTFail("expected unreadable, got \(answer)")
        }
    }

    func testSameURLIsSameWithoutFileAccess() {
        let missing = dir.appendingPathComponent("never-opened.ARW")
        let calls = SetsDuplicates.Calls(
            size: { _ in XCTFail("same URL must not be statted"); return 0 },
            hash: { _, _ in XCTFail("same URL must not be hashed"); return "" })

        XCTAssertEqual(SetsDuplicates.confirm([.init(a: missing, b: missing)], isCancelled: { false }, calls: calls), [.same])
    }

    func testSharedFileIsHashedOnceAcrossTenPairs() throws {
        let bytes = randomBytes(1 << 20)
        let shared = try put("shared.ARW", bytes: bytes)
        let others = try (0..<10).map { try put("copy-\($0).ARW", bytes: bytes) }
        var counts: [URL: Int] = [:]
        let calls = SetsDuplicates.Calls(
            size: { url in
                let number = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! NSNumber
                return number.int64Value
            },
            hash: { url, _ in
                counts[url, default: 0] += 1
                return try SetsFileOps.sha256(file: url)
            })

        let answers = SetsDuplicates.confirm(others.map { .init(a: shared, b: $0) }, isCancelled: { false }, calls: calls)
        XCTAssertEqual(answers, Array(repeating: .same, count: 10))
        XCTAssertEqual(counts[shared], 1)
        XCTAssertEqual(counts.values.reduce(0, +), 11)
    }

    func testCancellationAfterFirstFileKeepsCompletedAnswersAndCancelsRest() throws {
        let bytes = randomBytes(1 << 20)
        let a = try put("a.ARW", bytes: bytes)
        let b = try put("b.ARW", bytes: bytes)
        var cancelled = false
        var hashes = 0
        let calls = SetsDuplicates.Calls(
            size: { url in
                let number = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! NSNumber
                return number.int64Value
            },
            hash: { url, _ in
                hashes += 1
                let value = try SetsFileOps.sha256(file: url)
                if hashes == 1 { cancelled = true }
                return value
            })
        let pairs = [
            SetsDuplicates.Candidate(a: a, b: a),
            SetsDuplicates.Candidate(a: a, b: b),
            SetsDuplicates.Candidate(a: b, b: a)
        ]

        XCTAssertEqual(
            SetsDuplicates.confirm(pairs, isCancelled: { cancelled }, calls: calls),
            [.same, .unreadable("cancelled"), .unreadable("cancelled")])
        XCTAssertEqual(hashes, 1)
    }

    func testAlreadyMatchesCaseInsensitiveNameAndExactSize() {
        let card = [
            (name: "DSC00001.ARW", size: 10),
            (name: "dsc00002.arw", size: 20),
            (name: "DSC00003.ARW", size: 30)
        ]
        let shoot = [
            (name: "dsc00001.arw", size: 10),
            (name: "DSC00002.ARW", size: 21),
            (name: "OTHER.ARW", size: 30)
        ]

        XCTAssertEqual(SetsDuplicates.already(names: card, inShoot: shoot), 1)
    }
}
