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
        XCTAssertEqual(r.decoderSummary, "RAW 9")
        r.decoders.append("raw 8 (raw 9 failed: x)"); r.fallbacks.append("DSC00003.ARW")
        XCTAssertEqual(r.decoderSummary, "RAW 8 + RAW 9 · 1 file fell back")
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

    /// An export says what SetsExportMetadata allows and nothing else (docs/release/TRUST.md I7):
    /// a source with a location, serial numbers and a credit renders to a JPEG that keeps the credit
    /// and the capture time and loses the rest, and to a PNG with nothing refused.
    func testExportMetadataIsTheAllowlist() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("look-meta-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pipe = try LookPipeline(rules: LookTestRules.load())
        let plain = try pipe.png(pipe.ramp(steps: 16, columnWidth: 4, height: 16).image)
        let file = dir.appendingPathComponent("tagged.jpg")
        let src = try XCTUnwrap(CGImageSourceCreateWithData(plain as CFData, nil))
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil))
        let tags: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W"] as [CFString: Any],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:09:08 14:30:00", kCGImagePropertyExifBodySerialNumber: "1234567", kCGImagePropertyExifLensSerialNumber: "7654321"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "Sam", kCGImagePropertyTIFFCopyright: "© Sam", kCGImagePropertyTIFFMake: "SONY"],
        ]
        CGImageDestinationAddImageFromSource(dest, src, 0, tags as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        try (out as Data).write(to: file)
        for format in ["jpg", "png"] {
            let (data, _) = try SetsLookExport.render(raw: file, look: "ev:+0.3", px: 32, format: format, decoder: nil)
            let r = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let props = CGImageSourceCopyPropertiesAtIndex(r, 0, nil) as? [String: Any] ?? [:]
            XCTAssertNil(props["{GPS}"], format)
            XCTAssertEqual(SetsExportMetadata.refused(in: props), [], format)
            guard format == "jpg" else { continue }   // a PNG may carry them as XMP only; what matters there is what it doesn't carry
            let exif = props["{Exif}"] as? [String: Any], tiff = props["{TIFF}"] as? [String: Any]
            XCTAssertEqual(exif?["DateTimeOriginal"] as? String, "2026:09:08 14:30:00", format)
            XCTAssertEqual(tiff?["Artist"] as? String, "Sam", format)
            XCTAssertEqual(tiff?["Copyright"] as? String, "© Sam", format)
        }
    }
}
