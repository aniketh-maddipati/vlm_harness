import Foundation

/// SHA-256 (FIPS 180-4) with the slice of CryptoKit's API the app uses. Linux sandbox only.
public struct SHA256 {
    public struct Digest: Sequence {
        let bytes: [UInt8]
        public func makeIterator() -> IndexingIterator<[UInt8]> { bytes.makeIterator() }
    }
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]
    private var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    private var buffer: [UInt8] = []
    private var length: UInt64 = 0

    public init() {}

    public static func hash<D: DataProtocol>(data: D) -> Digest { var s = SHA256(); s.update(data: data); return s.finalize() }

    public mutating func update<D: DataProtocol>(data: D) {
        buffer.append(contentsOf: data); length += UInt64(data.count)
        var i = 0
        while buffer.count - i >= 64 { block(buffer[i..<i + 64]); i += 64 }
        buffer.removeFirst(i)
    }

    public func finalize() -> Digest {
        var s = self
        var tail = s.buffer + [0x80]
        while tail.count % 64 != 56 { tail.append(0) }
        let bits = length &* 8
        for i in (0..<8).reversed() { tail.append(UInt8(truncatingIfNeeded: bits >> (UInt64(i) * 8))) }
        var i = 0
        while i < tail.count { s.block(tail[i..<i + 64]); i += 64 }
        return Digest(bytes: s.h.flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> (24 - 8 * $0)) } })
    }

    private mutating func block(_ b: ArraySlice<UInt8>) {
        let r = { (x: UInt32, n: UInt32) in (x >> n) | (x << (32 - n)) }
        var w = [UInt32](repeating: 0, count: 64)
        let base = b.startIndex
        for t in 0..<16 { w[t] = (0..<4).reduce(0) { $0 << 8 | UInt32(b[base + t * 4 + $1]) } }
        for t in 16..<64 {
            let s0 = r(w[t - 15], 7) ^ r(w[t - 15], 18) ^ (w[t - 15] >> 3), s1 = r(w[t - 2], 17) ^ r(w[t - 2], 19) ^ (w[t - 2] >> 10)
            w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
        }
        var (a, bb, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
        for t in 0..<64 {
            let t1 = hh &+ (r(e, 6) ^ r(e, 11) ^ r(e, 25)) &+ ((e & f) ^ (~e & g)) &+ SHA256.k[t] &+ w[t]
            let t2 = (r(a, 2) ^ r(a, 13) ^ r(a, 22)) &+ ((a & bb) ^ (a & c) ^ (bb & c))
            (hh, g, f, e, d, c, bb, a) = (g, f, e, d &+ t1, c, bb, a, t1 &+ t2)
        }
        h = [h[0] &+ a, h[1] &+ bb, h[2] &+ c, h[3] &+ d, h[4] &+ e, h[5] &+ f, h[6] &+ g, h[7] &+ hh]
    }
}
