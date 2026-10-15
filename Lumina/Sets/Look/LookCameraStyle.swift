import Foundation

/// The Creative Style a Sony body shot with ("Standard", "Neutral", "Landscape", …): the look the
/// camera gave its own JPEG. The camera profile (`camera` stage, `prof:camera`) picks its numbers
/// by it, as Lightroom's Camera Matching profiles do. Sony writes it into the MakerNote (tag
/// 0xB020, ASCII), which sits in the Exif IFD; the MakerNote is an IFD (after a 12-byte "SONY DSC "
/// header on some bodies, none on the a7 III), with offsets from the start of the file.
nonisolated enum LookCameraStyle {
    static let tagExif: Int = 0x8769
    static let tagMakerNote: Int = 0x927C
    static let tagStyle: Int = 0xB020

    /// The style in `url`, lower-cased ("landscape"), or nil (not a Sony RAW, no tag). Reads a
    /// few directories, never the pixels.
    static func read(url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        return read { offset, count in
            guard (try? h.seek(toOffset: UInt64(offset))) != nil, let d = try? h.read(upToCount: count), d.count == count else { return nil }
            return d
        }
    }

    /// The same over any byte source (tests hand it a TIFF built in memory).
    static func read(_ bytes: (_ offset: Int, _ count: Int) -> Data?) -> String? {
        guard let head = bytes(0, 8) else { return nil }
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
        /// One directory's entries: (tag, type, count, where its 4 value bytes are).
        func entries(at offset: Int) -> [(tag: Int, type: Int, count: Int, value: Int)] {
            guard offset > 0, let n = bytes(offset, 2).map({ u16($0, 0) }), n > 0, n < 1024, let d = bytes(offset + 2, n * 12) else { return [] }
            return (0..<n).map { i in (u16(d, i * 12), u16(d, i * 12 + 2), u32(d, i * 12 + 4), offset + 2 + i * 12 + 8) }
        }
        func pointer(_ e: (tag: Int, type: Int, count: Int, value: Int)) -> Int? { bytes(e.value, 4).map { u32($0, 0) } }

        guard let exif = entries(at: u32(head, 4)).first(where: { $0.tag == tagExif }).flatMap(pointer),
              let note = entries(at: exif).first(where: { $0.tag == tagMakerNote }), note.count > 14, let at = pointer(note),
              let sig = bytes(at, 12),
              let style = entries(at: sig.starts(with: Array("SONY DSC ".utf8)) ? at + 12 : at).first(where: { $0.tag == tagStyle && $0.type == 2 }), style.count > 1, style.count <= 64 else { return nil }
        guard let raw = style.count <= 4 ? bytes(style.value, style.count) : pointer(style).flatMap({ bytes($0, style.count) }) else { return nil }
        let text = String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text.lowercased()
    }
}
