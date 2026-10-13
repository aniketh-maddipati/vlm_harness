import Foundation
import XCTest
@testable import Lumina

/// What a rendered export says about the photo (docs/release/TRUST.md I7): the allowlist, and
/// never a location, a serial number or an orientation. Foundation only, run on Linux too.
final class SetsExportMetadataTests: XCTestCase {
    static let raw: [String: Any] = [
        "{GPS}": ["Latitude": 51.5, "LatitudeRef": "N", "Longitude": 0.12, "LongitudeRef": "W"],
        "{TIFF}": ["Make": "SONY", "Model": "ILCE-7RM5", "Orientation": 6, "Software": "ILCE-7RM5 v2.00", "Artist": "Sam", "Copyright": "© Sam"],
        "{Exif}": ["DateTimeOriginal": "2026:09:08 14:30:00", "ExposureTime": 0.004, "FNumber": 2.8, "ISOSpeedRatings": [100],
                   "BodySerialNumber": "1234567", "LensSerialNumber": "7654321", "CameraOwnerName": "Sam", "LensModel": "FE 35mm F1.4 GM",
                   "MakerNote": "x", "UserComment": "x"],
        "{ExifAux}": ["SerialNumber": "1234567"],
        "{IPTC}": ["Byline": ["Sam"], "City": "London", "Country/PrimaryLocationName": "UK", "CopyrightNotice": "© Sam",
                   "ContactInfo": ["CiAdrCity": "London"]],
        "{MakerSony}": ["x": 1],
        "Orientation": 6,
    ]

    func testOnlyTheAllowlistIsWritten() {
        let f = SetsExportMetadata.fields(from: Self.raw)
        let names = Set(f.map { "\($0.dictionary).\($0.key)" })
        XCTAssertEqual(names, ["{TIFF}.Make", "{TIFF}.Model", "{TIFF}.Artist", "{TIFF}.Copyright",
                               "{Exif}.DateTimeOriginal", "{Exif}.ExposureTime", "{Exif}.FNumber", "{Exif}.ISOSpeedRatings", "{Exif}.LensModel",
                               "{IPTC}.Byline", "{IPTC}.CopyrightNotice"])
    }

    func testNoLocationSerialOrOrientationEverLeaves() {
        let names = SetsExportMetadata.fields(from: Self.raw).map { "\($0.dictionary).\($0.key)" }
        for n in names {
            XCTAssertFalse(n.hasPrefix("{GPS}") || n.contains("Serial") || n.hasSuffix("Orientation") || n.contains("City") || n.contains("Country"), n)
        }
    }

    func testKeepAndNeverDontMeet() {
        for (dict, keys) in SetsExportMetadata.keep {
            XCTAssertFalse(SetsExportMetadata.never.contains(dict), dict)
            for k in keys { XCTAssertFalse(SetsExportMetadata.never.contains("\(dict).\(k)"), "\(dict).\(k)") }
        }
    }

    func testRefusedFindsWhatMustNotBeThere() {
        XCTAssertEqual(SetsExportMetadata.refused(in: Self.raw), ["{ExifAux}", "{Exif}.BodySerialNumber", "{Exif}.CameraOwnerName", "{Exif}.LensSerialNumber",
                                                                  "{Exif}.MakerNote", "{Exif}.UserComment", "{GPS}", "{IPTC}.City",
                                                                  "{IPTC}.ContactInfo", "{IPTC}.Country/PrimaryLocationName", "{TIFF}.Orientation", "{TIFF}.Software"])
        XCTAssertEqual(SetsExportMetadata.refused(in: ["{TIFF}": ["Orientation": 1], "{Exif}": ["PixelXDimension": 64, "DateTimeOriginal": "x"]]), [],
                       "an upright orientation and the encoder's own sizes are not refused")
    }

    func testUnusableValuesStayOut() {
        let f = SetsExportMetadata.fields(from: ["{TIFF}": ["Artist": String(repeating: "a", count: 3000), "Make": "a\u{0}b", "Model": ["k": "v"]]])
        XCTAssertTrue(f.isEmpty, "\(f.map { $0.key })")
    }
}
