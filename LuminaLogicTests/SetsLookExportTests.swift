import CoreImage
import ImageIO
import XCTest
@testable import Lumina

/// Export's look renders (RAW 9 §2): the decoder outcome the result block names, the 8 s guard
/// and the per-file fallback, and the export job carrying the decoder per item.
final class SetsLookExportTests: XCTestCase {
    override func setUpWithError() throws {
        // SetsLookExport reads the bundled rules (or LUMINA_RULES): point it at the checkout's copy.
        if (try? LookRules.bundled()) == nil { setenv("LUMINA_RULES", LookTestRules.url().path, 1) }
        if (try? LookRules.bundled()) == nil { throw XCTSkip("rules-v1.json is neither bundled nor reachable through LUMINA_RULES") }
    }

    func testTimedReturnsOrThrowsTimeout() throws {
        XCTAssertEqual(try SetsLookExport.timed(1, true) { Data([1, 2]) }, Data([1, 2]))
        XCTAssertEqual(try SetsLookExport.timed(0, true) { Data([3]) }, Data([3]), "no guard without a limit")
        XCTAssertThrowsError(try SetsLookExport.timed(0.05, true) { Thread.sleep(forTimeInterval: 0.5); return Data() }) { XCTAssertTrue($0 is SetsLookExport.Timeout, "\($0)") }
        struct Boom: Error {}
        XCTAssertThrowsError(try SetsLookExport.timed(1, true) { throw Boom() }) { XCTAssertTrue($0 is Boom) }
    }

    func testOutcomeLabels() {
        XCTAssertEqual(SetsLookExport.Outcome(decoder: 9).label, "raw 9")
        XCTAssertEqual(SetsLookExport.Outcome(decoder: 8, fellBackFrom: 9, reason: "took more than 8 s").label, "raw 8 (raw 9 failed: took more than 8 s)")
        XCTAssertEqual(SetsLookExport.Outcome(decoder: nil).label, "embedded image")
        var r = SetsExportJob.Result()
        XCTAssertEqual(r.decoderSummary, "")
        r.decoders = ["raw 9", "raw 9"]
        XCTAssertEqual(r.decoderSummary, "raw 9")
        r.decoders.append("raw 8 (raw 9 failed: x)"); r.fallbacks.append("DSC00003.ARW")
        XCTAssertEqual(r.decoderSummary, "raw 8 + raw 9 · 1 file fell back")
    }

    /// A non-RAW (PNG) renders with no decoder and no fallback; a `nr` key in the look is accepted.
    func testRenderNonRAWHasNoDecoder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("look-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pipe = try LookPipeline(rules: LookTestRules.load())
        let file = dir.appendingPathComponent("ramp.png")
        try pipe.png(pipe.ramp(steps: 32, columnWidth: 4, height: 32).image).write(to: file)
        let (data, out) = try SetsLookExport.render(raw: file, look: "ev:+0.5 nr:40", px: 64, format: "png", decoder: 8)
        XCTAssertNil(out.decoder, "a PNG has no RAW decoder"); XCTAssertNil(out.fellBackFrom)
        XCTAssertEqual(out.label, "embedded image")
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual((CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int, 64)
        // The job records what each look item used.
        let job = SetsExportJob(label: "look", destination: dir.appendingPathComponent("out"), items: [.look(name: "a.png", source: file, look: "con:+10", px: 32, decoder: 8)])
        let r = job.run(journal: nil)
        XCTAssertEqual(r.n, 1); XCTAssertEqual(r.decoders, ["embedded image"]); XCTAssertTrue(r.fallbacks.isEmpty); XCTAssertEqual(r.renderMs.count, 1)
    }
}
