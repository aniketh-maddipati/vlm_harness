import Foundation

/// Port of `crc32` and `zip` from `design/handoff/lumina-cull/lumina-core.js`.
nonisolated enum CullCoreArchive {
    struct Entry: Equatable {
        var name: String
        var data: Data
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32<Bytes: Sequence>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in bytes { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    /// Stored (uncompressed) zip, byte-identical to the prototype's Blob.
    static func zip(_ entries: [Entry]) -> Data {
        var parts = Data(), central = Data()
        var offset: UInt32 = 0
        for entry in entries {
            let name = Data(entry.name.utf8), crc = crc32(entry.data), size = UInt32(truncatingIfNeeded: entry.data.count)
            var local = Data(count: 30)
            local.put32(0, 0x0403_4B50); local.put16(4, 20); local.put16(12, 0x21)
            local.put32(14, crc); local.put32(18, size); local.put32(22, size); local.put16(26, UInt16(truncatingIfNeeded: name.count))
            parts += local; parts += name; parts += entry.data

            var header = Data(count: 46)
            header.put32(0, 0x0201_4B50); header.put16(4, 20); header.put16(6, 20); header.put16(14, 0x21)
            header.put32(16, crc); header.put32(20, size); header.put32(24, size)
            header.put16(28, UInt16(truncatingIfNeeded: name.count)); header.put32(42, offset)
            central += header; central += name
            offset &+= UInt32(truncatingIfNeeded: 30 + name.count + entry.data.count)
        }
        var end = Data(count: 22)
        end.put32(0, 0x0605_4B50)
        end.put16(8, UInt16(truncatingIfNeeded: entries.count)); end.put16(10, UInt16(truncatingIfNeeded: entries.count))
        end.put32(12, UInt32(truncatingIfNeeded: central.count)); end.put32(16, offset)
        return parts + central + end
    }
}

private extension Data {
    mutating func put16(_ at: Int, _ value: UInt16) {
        self[at] = UInt8(value & 0xFF); self[at + 1] = UInt8(value >> 8)
    }

    mutating func put32(_ at: Int, _ value: UInt32) {
        for i in 0..<4 { self[at + i] = UInt8((value >> (8 * UInt32(i))) & 0xFF) }
    }
}
