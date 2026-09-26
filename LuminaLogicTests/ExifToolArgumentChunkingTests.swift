import XCTest
@testable import Lumina

/// `Process.run()` raises `NSInvalidArgumentException: too many arguments (4097) -- limit
/// is 4096` from `-[NSConcreteTask launchWithDictionary:error:]`. It is an Objective-C
/// exception, so `try` cannot catch it: crossing the limit terminates the app. A 4247-frame
/// card therefore crashed Lumina during "Reading dates…" rather than failing softly.
///
/// These pin that `batchCaptureDates` never builds an oversized argument vector. The count
/// assertions are the load-bearing ones — a regression there is not a failed test but a
/// dead process.
final class ExifToolArgumentChunkingTests: XCTestCase {

    private func paths(_ count: Int, length: Int = 60) -> [String] {
        let pad = String(repeating: "x", count: max(0, length - 20))
        return (0..<count).map { "/Volumes/T7/\(pad)/IMG_\($0).ARW" }
    }

    func testEveryChunkFitsUnderTheProcessArgumentLimit() {
        let flagCount = 5
        for count in [0, 1, 100, 4090, 4091, 4092, 4247, 9000] {
            let chunks = ExifToolService.argumentChunks(for: paths(count), reserving: flagCount)
            for chunk in chunks {
                XCTAssertLessThanOrEqual(
                    chunk.count + flagCount, ExifToolService.maximumArguments,
                    "a run of \(count) files produced an argument vector Process will reject "
                        + "fatally — this is a crash, not a failure"
                )
            }
        }
    }

    func testNoPathIsLostOrDuplicated() {
        for count in [1, 4247, 9000] {
            let input = paths(count)
            let flat = ExifToolService.argumentChunks(for: input, reserving: 5).flatMap { $0 }
            XCTAssertEqual(flat, input, "chunking must preserve every path, in order")
        }
    }

    func testTheByteBoundSplitsDeepPathsThatTheCountBoundWouldMiss() {
        // 3000 paths of 900 bytes is ~2.6 MB — well under 4096 arguments and well over
        // ARG_MAX, which is the case a count-only bound gets wrong.
        let deep = paths(3000, length: 900)
        let chunks = ExifToolService.argumentChunks(for: deep, reserving: 5)
        XCTAssertGreaterThan(chunks.count, 1, "deep paths must split on bytes, not only on count")
        for chunk in chunks {
            let bytes = chunk.reduce(0) { $0 + $1.utf8.count + 1 }
            XCTAssertLessThanOrEqual(bytes, ExifToolService.maximumArgumentBytes)
        }
    }

    func testASinglePathOverTheByteBoundStillGetsARun() {
        let huge = String(repeating: "z", count: ExifToolService.maximumArgumentBytes * 2)
        let chunks = ExifToolService.argumentChunks(for: [huge], reserving: 5)
        XCTAssertEqual(chunks.count, 1, "an unsplittable path must still be attempted, not dropped")
        XCTAssertEqual(chunks.first, [huge])
    }

    func testEmptyInputProducesNoRuns() {
        XCTAssertTrue(ExifToolService.argumentChunks(for: [], reserving: 5).isEmpty)
    }

    /// End to end: more files than `Process` will accept in one vector. Before chunking
    /// this call terminated the test process instead of returning.
    func testABatchLargerThanTheArgumentLimitReturnsInsteadOfCrashing() throws {
        try XCTSkipUnless(
            ExifToolService.isAvailable,
            "exiftool is required for this contract; install it with `brew install exiftool`."
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("exif-chunk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // 4300 > the 4096 limit. Empty files: this test is about the argument vector, and
        // every one of them still has to come back placed, by its modification time.
        var urls: [URL] = []
        for index in 0..<4300 {
            let url = directory.appendingPathComponent(String(format: "IMG_%05d.ARW", index))
            try Data().write(to: url)
            urls.append(url)
        }

        let dates = ExifToolService.batchCaptureDates(in: directory, files: urls)

        XCTAssertEqual(
            urls.filter { dates[$0.path] == nil }.count, 0,
            "every frame in an over-limit batch must come back with a date"
        )
    }
}
