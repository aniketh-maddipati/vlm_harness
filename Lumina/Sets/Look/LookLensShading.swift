import Foundation

/// The lens's corner shading, from the camera's own numbers. A Sony body writes the vignetting
/// correction for the lens, aperture and focus distance of each shot into the RAW
/// (`VignettingCorrParams`, TIFF tag 0x7032 in the raw SubIFD: a count, then that many radial
/// knots from the centre to the corner). Lightroom's lens profile does the same job from Adobe's
/// tables; Core Image's RAW decoder leaves the shading in. Reading the camera's values needs no
/// per-lens table and no fit: whatever lens was mounted, the body measured it.
///
/// The knot value → falloff relation (falloff = 2^(0.5 − 2^(v / 8192 − 1)), knots at
/// (i + 0.5) / (n − 1) of the half diagonal) is the one darktable's embedded-metadata lens
/// correction documents for Sony files (structure only, AGENTS.md: ideas cited, never code).
nonisolated struct LookLensShading: Equatable, Sendable {
    /// Radial knots, centre to corner, as the camera wrote them (0 = no falloff).
    var knots: [Int]

    static let tagParams: UInt16 = 0x7032
    static let tagSubIFDs: UInt16 = 0x014A

    /// The gain that undoes the falloff at each knot (≥ 1, 1 at the centre).
    var gains: [Double] { knots.map { Self.gain(knot: $0) } }

    static func gain(knot v: Int) -> Double {
        let falloff = pow(2, 0.5 - pow(2, Double(v) / 8192 - 1))
        return 1 / falloff
    }

    /// Where knot `i` of `n` sits, as a fraction of the half diagonal.
    static func position(_ i: Int, of n: Int) -> Double { n > 1 ? (Double(i) + 0.5) / Double(n - 1) : 0 }

    /// The gain at `r` (0 centre … 1 corner), linear between knots, flat outside them; `amount`
    /// scales the correction (0 none … 1 the camera's own).
    func gain(at r: Double, amount: Double = 1) -> Double {
        let g = gains
        guard let first = g.first, let last = g.last else { return 1 }
        let n = g.count
        var out = last
        if r <= Self.position(0, of: n) { out = first } else {
            for i in 1..<n where r <= Self.position(i, of: n) {
                let a = Self.position(i - 1, of: n), b = Self.position(i, of: n)
                out = g[i - 1] + (g[i] - g[i - 1]) * (r - a) / (b - a)
                break
            }
        }
        return 1 + (out - 1) * min(1, max(0, amount))
    }

    /// True when the camera recorded any falloff at all.
    var corrects: Bool { knots.contains { $0 != 0 } }

    // MARK: Reading the RAW

    /// The shading the camera wrote into `url`, or nil (not a Sony RAW, no tag, an odd file).
    /// Reads the TIFF directories only: a few kilobytes, never the pixels.
    static func read(url: URL) -> LookLensShading? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        return read { offset, count in
            guard (try? h.seek(toOffset: UInt64(offset))) != nil, let d = try? h.read(upToCount: count), d.count == count else { return nil }
            return d
        }
    }

    /// The same over any byte source (tests hand it a TIFF built in memory).
    static func read(_ bytes: (_ offset: Int, _ count: Int) -> Data?) -> LookLensShading? {
        guard let head = bytes(0, 8), head.count == 8 else { return nil }
        let little: Bool
        switch (head[0], head[1]) {
        case (0x49, 0x49): little = true
        case (0x4D, 0x4D): little = false
        default: return nil
        }
        func u16(_ d: Data, _ at: Int) -> Int {
            let a = Int(d[d.startIndex + at]), b = Int(d[d.startIndex + at + 1])
            return little ? a | b << 8 : a << 8 | b
        }
        func u32(_ d: Data, _ at: Int) -> Int {
            let b = (0..<4).map { Int(d[d.startIndex + at + $0]) }
            return little ? b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24 : b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]
        }
        guard u16(head, 2) == 42 else { return nil }

        /// One directory's entries: (tag, type, count, the 4 value bytes' offset in the file).
        func entries(at offset: Int) -> [(tag: Int, type: Int, count: Int, value: Int)] {
            guard offset > 0, let n = bytes(offset, 2).map({ u16($0, 0) }), n > 0, n < 512, let d = bytes(offset + 2, n * 12) else { return [] }
            return (0..<n).map { i in (u16(d, i * 12), u16(d, i * 12 + 2), u32(d, i * 12 + 4), offset + 2 + i * 12 + 8) }
        }
        func params(in dir: [(tag: Int, type: Int, count: Int, value: Int)]) -> LookLensShading? {
            guard let e = dir.first(where: { $0.tag == Int(tagParams) }), e.type == 8 || e.type == 3, e.count >= 2, e.count <= 64 else { return nil }
            let size = e.count * 2
            guard let at = size <= 4 ? e.value : bytes(e.value, 4).map({ u32($0, 0) }), let d = bytes(at, size) else { return nil }
            let v = (0..<e.count).map { i -> Int in let x = u16(d, i * 2); return x >= 0x8000 ? x - 0x10000 : x }
            // The first value is how many knots follow.
            let n = v[0]
            guard n >= 2, n <= v.count - 1 else { return nil }
            return LookLensShading(knots: Array(v[1...n]))
        }

        let ifd0 = entries(at: u32(head, 4))
        if let s = params(in: ifd0) { return s }
        guard let sub = ifd0.first(where: { $0.tag == Int(tagSubIFDs) }), sub.count >= 1, sub.count <= 8 else { return nil }
        var offsets: [Int] = []
        if sub.count == 1 { if let d = bytes(sub.value, 4) { offsets = [u32(d, 0)] } }
        else if let at = bytes(sub.value, 4).map({ u32($0, 0) }), let d = bytes(at, sub.count * 4) { offsets = (0..<sub.count).map { u32(d, $0 * 4) } }
        for o in offsets { if let s = params(in: entries(at: o)) { return s } }
        return nil
    }
}
