import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared by the two fuzz tools (Q4, stress matrix 7): synthetic ARWs, the process's memory, the
/// watchdog that stops a run before a hostile input takes the Mac's memory, JSON lines out.
enum Fuzz {
    /// The process's memory footprint (what Activity Monitor shows), in bytes.
    static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    /// Exits the process (code 4) with one JSON line when its footprint passes `limit`: a decode
    /// that would take gigabytes is a finding, not something to let run on the user's Mac.
    static func memoryWatchdog(limit: Int64, current: @escaping @Sendable () -> String) {
        let t = Thread {
            while true {
                let f = footprint()
                if f > limit {
                    emit(["event": "memory", "case": current(), "footprintMB": f >> 20, "limitMB": limit >> 20])
                    fflush(stdout)
                    _exit(4)
                }
                usleep(20_000)
            }
        }
        t.qualityOfService = .userInteractive
        t.start()
    }

    static let out = FileHandle.standardOutput
    static func emit(_ o: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return }
        out.write(d); out.write(Data([10]))
    }

    /// A seeded PRNG (SplitMix64), so a case number names the same input on every run.
    struct Rand {
        var s: UInt64
        init(_ seed: UInt64) { s = seed &+ 0x9E3779B97F4A7C15 }
        mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
        mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
        mutating func byte() -> UInt8 { UInt8(truncatingIfNeeded: next()) }
    }

    // MARK: Synthetic pictures

    /// A detailed test picture (gradients, hairlines, blocks) as a JPEG, `w` × `h`.
    static func jpeg(w: Int, h: Int, seed: Int, quality: Double = 0.85) -> Data {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        var r = Rand(UInt64(seed))
        for y in stride(from: 0, to: h, by: 8) {
            ctx.setFillColor(CGColor(srgbRed: CGFloat(y) / CGFloat(h), green: 0.4, blue: 1 - CGFloat(y) / CGFloat(h), alpha: 1))
            ctx.fill(CGRect(x: 0, y: y, width: w, height: 8))
        }
        for _ in 0..<200 {
            ctx.setFillColor(CGColor(srgbRed: CGFloat(r.int(255)) / 255, green: CGFloat(r.int(255)) / 255, blue: CGFloat(r.int(255)) / 255, alpha: 1))
            ctx.fill(CGRect(x: r.int(w), y: r.int(h), width: 2 + r.int(40), height: 1 + r.int(30)))
        }
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    /// A synthetic Sony-style ARW (TIFF, little-endian), as `Tests/web/lib.mjs` `tiff()` makes them:
    /// IFD0 with Model, Orientation, JPEGInterchangeFormat(+Length) and an Exif IFD (DateTimeOriginal,
    /// ExposureTime, ISO, FocalLength). The JPEG sits at `jpegAt` (4096 = inside the 256 KB head, as
    /// a Sony body puts it; past 256 KB = read from the card); the file is padded to `pad`.
    static func arw(jpeg: Data, orient: Int = 1, jpegAt: Int = 4096, pad: Int = 300_000, date: String = "2026:09:08 10:00:00", model: String = "ILCE-7M4") -> Data {
        var b = Data(count: max(pad, jpegAt + jpeg.count + 16))
        func u16(_ o: Int, _ v: Int) { b[o] = UInt8(v & 0xFF); b[o + 1] = UInt8((v >> 8) & 0xFF) }
        func u32(_ o: Int, _ v: Int) { for i in 0..<4 { b[o + i] = UInt8((v >> (8 * i)) & 0xFF) } }
        b[0] = 0x49; b[1] = 0x49; u16(2, 42); u32(4, 8)
        let ifd0 = 8, n0 = 5, exif = ifd0 + 2 + n0 * 12 + 4, n1 = 4, data = exif + 2 + n1 * 12 + 4
        var dp = data
        func put(_ s: String) -> Int { let o = dp; for (i, c) in s.utf8.enumerated() { b[o + i] = c }; dp += s.utf8.count + 1; if dp % 2 == 1 { dp += 1 }; return o }
        func rat(_ a: Int, _ d: Int) -> Int { let o = dp; u32(o, a); u32(o + 4, d); dp += 8; return o }
        func ent(_ base: Int, _ i: Int, _ tag: Int, _ type: Int, _ cnt: Int, _ val: Int) {
            let e = base + 2 + i * 12; u16(e, tag); u16(e + 2, type); u32(e + 4, cnt)
            if type == 3 && cnt == 1 { u16(e + 8, val) } else { u32(e + 8, val) }
        }
        let mo = put(model), dto = put(date), eo = rat(1, 250), fo = rat(50, 1)
        u16(ifd0, n0)
        ent(ifd0, 0, 0x0110, 2, model.utf8.count + 1, mo)
        ent(ifd0, 1, 0x0112, 3, 1, orient)
        ent(ifd0, 2, 0x0201, 4, 1, jpegAt)
        ent(ifd0, 3, 0x0202, 4, 1, jpeg.count)
        ent(ifd0, 4, 0x8769, 4, 1, exif)
        u32(ifd0 + 2 + n0 * 12, 0)
        u16(exif, n1)
        ent(exif, 0, 0x829A, 5, 1, eo)
        ent(exif, 1, 0x8827, 3, 1, 400)
        ent(exif, 2, 0x9003, 2, date.utf8.count + 1, dto)
        ent(exif, 3, 0x920A, 5, 1, fo)
        u32(exif + 2 + n1 * 12, 0)
        b.replaceSubrange(jpegAt ..< jpegAt + jpeg.count, with: jpeg)
        return b
    }

    static func hex(_ s: String) -> Data {
        var d = Data(capacity: s.count / 2); var i = s.startIndex
        while i < s.endIndex, let j = s.index(i, offsetBy: 2, limitedBy: s.endIndex) { d.append(UInt8(s[i ..< j], radix: 16) ?? 0); i = j }
        return d
    }

    /// A case's input: `base` cut to `trunc` bytes (if set), then each patch `[offset, hex]` written
    /// over it (growing the file when a patch is past its end). The same rule as `cases.mjs`.
    static func mutate(_ base: Data, trunc: Int?, patches: [[Any]]) -> Data {
        var d = trunc.map { base.prefix(max(0, $0)) } ?? base
        for p in patches {
            guard p.count == 2, let at = (p[0] as? NSNumber)?.intValue, let hx = p[1] as? String, at >= 0 else { continue }
            let bytes = hex(hx)
            if at + bytes.count > d.count { d.append(Data(count: at + bytes.count - d.count)) }
            d.replaceSubrange(at ..< at + bytes.count, with: bytes)
        }
        return d
    }
}
