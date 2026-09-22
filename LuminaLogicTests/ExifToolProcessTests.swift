import XCTest
@testable import Lumina

/// The child-process contract behind every exiftool call: output is drained
/// before exit is awaited, so a large result cannot wedge the parent.
final class ExifToolProcessTests: XCTestCase {

    /// 300 KB is well past the 64 KB pipe buffer. Before the fix this call
    /// never returned: the child blocked on write, the parent on exit.
    func testOutputLargerThanThePipeBufferIsDrained() throws {
        let started = CFAbsoluteTimeGetCurrent()
        let result = try ExifToolService.captureOutput(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 300000 /dev/zero"]
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.data.count, 300_000)
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - started, 10, "a drained pipe does not wait on anything")
    }

    func testStderrCannotWedgeEither() throws {
        let result = try ExifToolService.captureOutput(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 200000 /dev/zero 1>&2; printf ok"]
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(String(decoding: result.data, as: UTF8.self), "ok")
    }

    func testExitStatusIsReported() throws {
        let result = try ExifToolService.captureOutput(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "exit 3"]
        )
        XCTAssertEqual(result.status, 3)
    }
}
