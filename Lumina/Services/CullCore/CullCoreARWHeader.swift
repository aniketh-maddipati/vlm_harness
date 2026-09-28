import Foundation

/// Port of `parseHead` from `design/handoff/lumina-cull/lumina-core.js`.
/// Sony ARW (TIFF) header → capture time, exposure, focal length, EV comp, ISO, orientation,
/// and the largest embedded JPEG preview.
nonisolated struct CullCoreARWHeader: Equatable {
    struct Preview: Equatable {
        var offset: UInt32
        var length: UInt32
    }

    /// EXIF DateTimeOriginal, e.g. `2026:09:26 07:00:00`.
    var date: String?
    /// Exposure time in seconds.
    var exposure: Double?
    var focalLength: Double?
    var exposureBias: Double?
    var iso: UInt32?
    var orientation: UInt32?
    var preview: Preview?

    /// `bytes` is the head of the file (the prototype reads the first 256 KB); `fileSize` bounds preview offsets.
    /// Returns nil for anything that is not a TIFF (the JS throws on 2–7 byte inputs; this returns nil).
    static func parse(_ bytes: [UInt8], fileSize: Int) -> CullCoreARWHeader? {
        guard bytes.count >= 8 else { return nil }
        let le = bytes[0] == 0x49 && bytes[1] == 0x49
        if !le && !(bytes[0] == 0x4D && bytes[1] == 0x4D) { return nil }
        var reader = Reader(bytes: bytes, littleEndian: le, fileSize: fileSize)
        reader.walk(reader.u32(4), depth: 0)
        // Stable sort, largest first — same as the JS Array.prototype.sort.
        let largest = reader.jpegs.enumerated()
            .sorted { $0.element.length != $1.element.length ? $0.element.length > $1.element.length : $0.offset < $1.offset }
            .first?.element
        var out = reader.out
        out.preview = largest
        return out
    }

    private struct Reader {
        let bytes: [UInt8]
        let littleEndian: Bool
        let fileSize: Int
        var seen = Set<UInt32>()
        var jpegs: [Preview] = []
        var out = CullCoreARWHeader()

        func u16(_ o: Int) -> UInt32 {
            let a = UInt32(bytes[o]), b = UInt32(bytes[o + 1])
            return littleEndian ? a | b << 8 : a << 8 | b
        }

        func u32(_ o: Int) -> UInt32 {
            let b = (0..<4).map { UInt32(bytes[o + $0]) }
            return littleEndian ? b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24 : b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]
        }

        func inBounds(_ o: Int) -> Bool { o >= 0 && o + 4 <= bytes.count }

        func string(_ p: Int, _ n: Int) -> String {
            var scalars = String.UnicodeScalarView()
            var i = 0
            while i < n && p + i < bytes.count {
                let c = bytes[p + i]
                if c == 0 { break }
                scalars.append(Unicode.Scalar(c))
                i += 1
            }
            return String(scalars).jsTrimmed
        }

        func rational(_ p: Int, signed: Bool) -> Double? {
            guard inBounds(p + 4) else { return nil }
            if signed {
                return Double(Int32(bitPattern: u32(p))) / Double(Int32(bitPattern: u32(p + 4)))
            }
            return Double(u32(p)) / Double(u32(p + 4))
        }

        mutating func walk(_ offset: UInt32, depth: Int) {
            let off = Int(offset)
            if offset == 0 || seen.contains(offset) || depth > 6 || off + 2 > bytes.count { return }
            seen.insert(offset)
            let n = Int(u16(off))
            if n == 0 || n > 1000 || off + 2 + n * 12 + 4 > bytes.count { return }
            var jpegOffset: UInt32 = 0, jpegLength: UInt32 = 0
            var subIFDs: [UInt32] = []
            for i in 0..<n {
                let e = off + 2 + i * 12
                let tag = u16(e), type = u16(e + 2), count = u32(e + 4), vo = e + 8
                let value = type == 3 && count == 1 ? u16(vo) : u32(vo)
                let pointer = count > 4 ? Int(u32(vo)) : vo
                switch tag {
                case 0x0201: jpegOffset = value
                case 0x0202: jpegLength = value
                case 0x8769: subIFDs.append(value)
                case 0x9003 where out.date?.isEmpty ?? true: out.date = string(pointer, Int(count))
                case 0x829A: out.exposure = rational(Int(u32(vo)), signed: false)
                case 0x920A: out.focalLength = rational(Int(u32(vo)), signed: false)
                case 0x9204: out.exposureBias = rational(Int(u32(vo)), signed: true)
                case 0x8827: out.iso = value
                case 0x0112 where (out.orientation ?? 0) == 0: out.orientation = value
                default: break
                }
            }
            if jpegOffset != 0 && jpegLength != 0 && Int(jpegOffset) + Int(jpegLength) <= fileSize {
                jpegs.append(Preview(offset: jpegOffset, length: jpegLength))
            }
            for sub in subIFDs { walk(sub, depth: depth + 1) }
            walk(u32(off + 2 + n * 12), depth: depth + 1)
        }
    }
}

nonisolated extension String {
    /// `String.prototype.trim` — strips JS WhiteSpace and LineTerminator code points.
    var jsTrimmed: String {
        let js: Set<Unicode.Scalar> = [
            "\u{09}", "\u{0A}", "\u{0B}", "\u{0C}", "\u{0D}", "\u{20}", "\u{A0}", "\u{1680}",
            "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}", "\u{2005}", "\u{2006}", "\u{2007}",
            "\u{2008}", "\u{2009}", "\u{200A}", "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}", "\u{FEFF}",
        ]
        var scalars = Array(unicodeScalars)
        while let first = scalars.first, js.contains(first) { scalars.removeFirst() }
        while let last = scalars.last, js.contains(last) { scalars.removeLast() }
        return String(String.UnicodeScalarView(scalars))
    }
}
