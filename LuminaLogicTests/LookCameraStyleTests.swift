import Foundation
import XCTest
@testable import Lumina

/// The Creative Style from a Sony MakerNote, read from a TIFF built in memory (no photo).
final class LookCameraStyleTests: XCTestCase {
    /// IFD0 → Exif IFD → MakerNote (an IFD, after "SONY DSC \0\0\0" when `header`) → 0xB020 ASCII.
    private func tiff(style: String, header: Bool = false, bigEndian: Bool = false) -> Data {
        func u16(_ v: Int) -> [UInt8] { bigEndian ? [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] : [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] { bigEndian ? [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
                                                  : [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)] }
        func entry(_ tag: Int, _ type: Int, _ count: Int, _ value: Int) -> [UInt8] { u16(tag) + u16(type) + u32(count) + u32(value) }
        // IFD0 at 8 (18 bytes), Exif IFD at 26 (18 bytes), MakerNote at 44, its IFD (18 bytes), then the text.
        let text = Array(style.utf8) + [0]
        let note = 44, ifd = note + (header ? 12 : 0), textAt = ifd + 18
        var d = Data((bigEndian ? [0x4D, 0x4D] : [0x49, 0x49]) + u16(42) + u32(8))
        d.append(contentsOf: u16(1) + entry(0x8769, 4, 1, 26) + u32(0))
        d.append(contentsOf: u16(1) + entry(0x927C, 7, 18 + (header ? 12 : 0) + text.count, note) + u32(0))
        if header { d.append(contentsOf: Array("SONY DSC ".utf8) + [0, 0, 0]) }
        d.append(contentsOf: u16(1) + entry(0xB020, 2, text.count, textAt) + u32(0))
        XCTAssertEqual(d.count, textAt)
        d.append(contentsOf: text)
        return d
    }

    private func read(_ d: Data) -> String? {
        LookCameraStyle.read { o, n in o >= 0 && o + n <= d.count ? d.subdata(in: o..<(o + n)) : nil }
    }

    func testReadsTheStyleWithAndWithoutTheSonyHeader() {
        XCTAssertEqual(read(tiff(style: "Landscape")), "landscape", "the a7 III: no header")
        XCTAssertEqual(read(tiff(style: "Standard", header: true)), "standard")
        XCTAssertEqual(read(tiff(style: "Neutral", bigEndian: true)), "neutral")
    }

    func testNotATiffOrNoStyleIsNil() {
        XCTAssertNil(read(Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0])))
        XCTAssertNil(read(Data()))
        var other = tiff(style: "Deep")
        other[46] = 0x21                            // the MakerNote's tag becomes 0xB021
        XCTAssertNil(read(other))
        XCTAssertNil(LookCameraStyle.read(url: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).ARW")))
    }
}
