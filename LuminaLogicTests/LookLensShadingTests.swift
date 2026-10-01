import Foundation
import XCTest
@testable import Lumina

/// The camera's vignetting numbers: read from a TIFF built in memory (no photo), the gain curve
/// they make, and how the amount scales it. Foundation only, so it runs on Linux too.
final class LookLensShadingTests: XCTestCase {
    /// A little-endian TIFF: IFD0 with a SubIFDs pointer, a SubIFD holding tag 0x7032 (SSHORT).
    private func tiff(params: [Int16], inIFD0: Bool = false, bigEndian: Bool = false) -> Data {
        var d = Data()
        func u16(_ v: Int) -> [UInt8] { bigEndian ? [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] : [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] { bigEndian ? [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
                                                  : [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)] }
        func entry(_ tag: Int, _ type: Int, _ count: Int, _ value: Int) -> [UInt8] { u16(tag) + u16(type) + u32(count) + u32(value) }
        d.append(contentsOf: (bigEndian ? [0x4D, 0x4D] : [0x49, 0x49]) + u16(42) + u32(8))
        // IFD0 at 8: one entry (12 bytes) + next (4) → ends at 26. SubIFD at 26, its data at 44.
        let paramsAt = 44
        if inIFD0 {
            d.append(contentsOf: u16(1) + entry(0x7032, 8, params.count, paramsAt) + u32(0))
            d.append(contentsOf: [UInt8](repeating: 0, count: paramsAt - d.count))
        } else {
            d.append(contentsOf: u16(1) + entry(0x014A, 4, 1, 26) + u32(0))
            d.append(contentsOf: u16(1) + entry(0x7032, 8, params.count, paramsAt) + u32(0))
        }
        XCTAssertEqual(d.count, paramsAt)
        for p in params { d.append(contentsOf: u16(Int(UInt16(bitPattern: p)))) }
        return d
    }

    private func read(_ d: Data) -> LookLensShading? {
        LookLensShading.read { o, n in o >= 0 && o + n <= d.count ? d.subdata(in: o..<(o + n)) : nil }
    }

    func testReadsTheKnotsFromTheRawSubIFD() {
        let wideOpen: [Int16] = [16, 0, 48, 416, 1024, 1808, 2656, 3552, 4496, 5456, 6432, 7424, 8400, 9376, 10336, 11264, 12160]
        XCTAssertEqual(read(tiff(params: wideOpen))?.knots, wideOpen.dropFirst().map(Int.init))
        XCTAssertEqual(read(tiff(params: wideOpen, bigEndian: true))?.knots, wideOpen.dropFirst().map(Int.init))
        XCTAssertEqual(read(tiff(params: wideOpen, inIFD0: true))?.knots.count, 16)
        // A stopped-down frame uses 11 of the 16 slots: the count says so, the zeros after it are padding.
        let f16: [Int16] = [11, 0, 16, 68, 152, 264, 404, 572, 768, 984, 1212, 1444, 0, 0, 0, 0, 0]
        XCTAssertEqual(read(tiff(params: f16))?.knots, [0, 16, 68, 152, 264, 404, 572, 768, 984, 1212, 1444])
    }

    func testNotATiffOrNoTagIsNil() {
        XCTAssertNil(read(Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0])))
        XCTAssertNil(read(Data()))
        XCTAssertNil(read(tiff(params: [40, 1, 2])), "a count larger than the values is not trusted")
        var noTag = tiff(params: [2, 0, 100])
        noTag[28] = 0x33                         // the SubIFD's tag becomes 0x7033
        XCTAssertNil(read(noTag))
        XCTAssertNil(LookLensShading.read(url: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).ARW")))
    }

    func testGainIsOneAtTheCentreAndGrowsToTheCorner() {
        let s = LookLensShading(knots: [0, 48, 416, 1024, 1808, 2656, 3552, 4496, 5456, 6432, 7424, 8400, 9376, 10336, 11264, 12160])
        XCTAssertTrue(s.corrects)
        XCTAssertEqual(s.gain(at: 0), 1, accuracy: 1e-9)
        var last = 1.0
        for i in 0...100 { let g = s.gain(at: Double(i) / 100); XCTAssertGreaterThanOrEqual(g, last - 1e-12, "monotonic at \(i)"); last = g }
        // FE 85mm at f/1.8: the camera asks for 0.85 stops at the corner.
        XCTAssertEqual(log2(s.gain(at: 1)), 0.85, accuracy: 0.01)
        XCTAssertEqual(LookLensShading.gain(knot: 0), 1, accuracy: 1e-12)
        XCTAssertFalse(LookLensShading(knots: [0, 0, 0]).corrects)
        XCTAssertEqual(LookLensShading(knots: []).gain(at: 0.5), 1)
    }

    func testAmountScalesTheCorrection() {
        let s = LookLensShading(knots: [0, 2000, 4000, 8000])
        let full = s.gain(at: 1)
        XCTAssertEqual(s.gain(at: 1, amount: 0), 1, accuracy: 1e-12)
        XCTAssertEqual(s.gain(at: 1, amount: 0.5), 1 + (full - 1) / 2, accuracy: 1e-12)
        XCTAssertEqual(s.gain(at: 1, amount: 3), full, accuracy: 1e-12, "clamped to the camera's own")
    }
}
