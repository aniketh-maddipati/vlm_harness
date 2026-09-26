import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Lumina

/// `exiftool` exits non-zero when *any* input is unreadable, having already written
/// valid JSON for every other file. `batchCaptureDates` used to throw that output away
/// and return file modification times for the **whole shoot**.
///
/// Measured on `/Volumes/T7/Photos/DCIM/100MSDCF` (2026-09-25): one zero-byte `DSC05252.ARW`
/// among 381 frames produced 58 KB of good JSON, exit 1, and a chronology rebuilt from copy
/// times — 42 chapters where the capture times give 35, and six RAW/JPEG pairs whose cover
/// (and so whose `ShootFrame.id`) flipped because the JPEG's copy time sorted first.
///
/// The contract these tests pin: one unreadable file costs that file its capture date and
/// nothing else.
final class ExifToolDateFallbackTests: XCTestCase {

    /// Far from any plausible EXIF value, so a date sourced from mtime is unmistakable.
    private let mtimeMarker = Date(timeIntervalSince1970: 978_307_200)  // 2001-01-01
    private let exifText = "2024:11:23 16:02:49"

    private var directory: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ExifToolService.isAvailable,
            "exiftool is required for this contract; install it with `brew install exiftool`."
        )
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("exif-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testOneUnreadableFileDoesNotDiscardEveryOtherDate() throws {
        let good = try writeJPEG(named: "GOOD0001.JPG", exif: exifText)
        let empty = try writeEmptyFile(named: "BAD00002.ARW")

        let dates = ExifToolService.batchCaptureDates(in: directory, files: [good, empty])

        let goodDate = try XCTUnwrap(dates[good.path], "the readable frame lost its date entirely")
        XCTAssertEqual(
            goodDate,
            try XCTUnwrap(parseExif(exifText)),
            "the readable frame fell back to its modification time because a *different* "
                + "file was unreadable — one bad frame must not cost the shoot its chronology"
        )
        XCTAssertNotEqual(
            goodDate, mtimeMarker,
            "the readable frame's date is its mtime marker, i.e. the whole-shoot fallback fired"
        )
    }

    func testTheUnreadableFileItselfStillFallsBackToItsModificationTime() throws {
        let good = try writeJPEG(named: "GOOD0001.JPG", exif: exifText)
        let empty = try writeEmptyFile(named: "BAD00002.ARW")

        let dates = ExifToolService.batchCaptureDates(in: directory, files: [good, empty])

        XCTAssertEqual(
            dates[empty.path], mtimeMarker,
            "a frame with no readable EXIF must still be placed, by its modification time"
        )
    }

    func testAnAllReadableFolderIsUnaffected() throws {
        let first = try writeJPEG(named: "GOOD0001.JPG", exif: exifText)
        let second = try writeJPEG(named: "GOOD0002.JPG", exif: "2024:11:23 16:05:48")

        let dates = ExifToolService.batchCaptureDates(in: directory, files: [first, second])

        XCTAssertEqual(dates[first.path], try XCTUnwrap(parseExif(exifText)))
        XCTAssertEqual(dates[second.path], try XCTUnwrap(parseExif("2024:11:23 16:05:48")))
    }

    // MARK: - fixtures

    /// A real 1x1 JPEG carrying `DateTimeOriginal`, with its modification time pinned to
    /// `mtimeMarker` so an mtime-sourced answer is distinguishable from an EXIF-sourced one.
    private func writeJPEG(named name: String, exif: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: exif]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "could not write the fixture JPEG")
        try FileManager.default.setAttributes([.modificationDate: mtimeMarker], ofItemAtPath: url.path)
        return url
    }

    private func writeEmptyFile(named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data().write(to: url)
        try FileManager.default.setAttributes([.modificationDate: mtimeMarker], ofItemAtPath: url.path)
        return url
    }

    /// The same parse `ExifToolService` applies: system time zone, no offset handling.
    private func parseExif(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }
}
