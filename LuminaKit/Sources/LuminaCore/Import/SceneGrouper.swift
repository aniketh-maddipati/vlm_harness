import Foundation

// WP-2. From files to a shoot (R-15, R-16): scenes by subfolder and by gaps of more than 30 minutes
// in capture time, bursts of frames at most 2 s apart with the same shape, at most 8 to a burst.
// Ids come from the file's identity, so the same folder gives the same shoot every time it is
// opened and decisions find their photos again (R-19).

public enum SceneGrouper {
    public static let sceneGap: TimeInterval = 30 * 60
    public static let burstGap: TimeInterval = 2
    public static let burstMax = 8

    /// `name` is the shoot's name, and the title of scenes whose files sit in no folder.
    public static func group(_ items: [ImportItem], name: String = "Folder") -> Shoot {
        struct Row { var item: ImportItem; var at: Date? }
        let rows = items.map { Row(item: $0, at: $0.shot ?? $0.modified) }.sorted { a, b in
            let ta = a.at ?? .distantPast, tb = b.at ?? .distantPast
            return ta != tb ? ta < tb : a.item.rel.compare(b.item.rel, options: [.numeric]) == .orderedAscending
        }
        var photos: [Photo] = [], scenes: [PhotoScene] = [], bursts: [Burst] = []
        var seen = Set<String>(), last: Row?, lastDir: String?, open: Int?    // `open`: the burst still taking frames
        photos.reserveCapacity(rows.count)

        for row in rows {
            let it = row.item, id = photoID(it)
            guard seen.insert(id).inserted else { continue }
            let dir = folder(it.rel) ?? name
            let gap = last.flatMap { l in row.at.flatMap { t in l.at.map { t.timeIntervalSince($0) } } }
            if last == nil || dir != lastDir || (gap ?? 0) > sceneGap {
                scenes.append(PhotoScene(id: "r\(scenes.count)", index: scenes.count, start: row.at, hm: row.at.map { String(clock($0).prefix(5)) } ?? "", title: dir, ids: []))
                open = nil
            }
            let si = scenes.count - 1
            // A burst: the frame before it in this scene was at most 2 s earlier and the same shape.
            var burst: String?
            if let l = last, let g = gap, !scenes[si].ids.isEmpty, g <= burstGap, abs(it.aspect - l.item.aspect) < 0.01 {
                if let b = open, bursts[b].ids.count >= burstMax {
                    open = nil                                                           // full: this frame stands alone
                } else {
                    if open == nil, photos[photos.count - 1].burst == nil {
                        let first = photos.count - 1
                        bursts.append(Burst(id: "g" + photos[first].id, ids: [photos[first].id]))
                        photos[first].burst = bursts[bursts.count - 1].id
                        open = bursts.count - 1
                    }
                    if let b = open { bursts[b].ids.append(id); burst = bursts[b].id }
                }
            } else { open = nil }

            let x = it.exif
            photos.append(Photo(id: id, file: fileName(it.rel), scene: si, burst: burst, aspect: it.aspect > 0 && it.aspect.isFinite ? it.aspect : 1.5,
                                shot: row.at, time: row.at.map(clock), camera: camera(x), lens: x?.lens,
                                focal: x?.focal.map { $0.rounded() }, aperture: x?.fNumber.map { ($0 * 10).rounded() / 10 },
                                shutter: x?.exposure.map(shutter), iso: x?.iso,
                                source: it.url.map { .file($0) } ?? .demo(seed: photos.count, bw: false),
                                suggested: false, rel: it.rel, size: it.size, modified: it.modified))
            scenes[si].ids.append(id)
            last = row; lastDir = dir
        }
        var span: String?
        if let first = scenes.first?.hm, !first.isEmpty, let end = photos.last?.time { span = "\(first)–\(end.prefix(5))" }
        return Shoot(photos: photos, scenes: scenes, bursts: bursts, name: name, label: "Folder · \(name)", span: span, local: true, key: "folder-\(name)")
    }

    /// Stable per file: the same relative path, size and modified time is the same photo (R-14).
    public static func photoID(_ item: ImportItem) -> String { "L" + hash(item.dedupeKey) }

    /// FNV-1a, 64 bit: the same on every launch (Swift's own hashes are seeded per process).
    public static func hash(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01b3 }
        return String(h, radix: 36)
    }

    /// The folder a file sits in ("Trip/Day 1/a.jpg" → "Day 1"); nil for a loose file.
    static func folder(_ rel: String) -> String? {
        let parts = rel.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count > 1 ? String(parts[parts.count - 2]) : nil
    }
    static func fileName(_ rel: String) -> String {
        let n = (rel.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? rel).trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? rel : n
    }
    /// "hh:mm:ss" on this Mac's clock.
    static func clock(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: d)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
    /// "Canon" + "Canon EOS R6" → "Canon EOS R6"; "SONY" + "ILCE-7M4" → "SONY ILCE-7M4".
    static func camera(_ x: EXIF?) -> String? {
        guard let x else { return nil }
        var model = x.model
        if let make = x.make, let m = model, m.lowercased().hasPrefix(make.lowercased()) { model = String(m.dropFirst(make.count)).trimmingCharacters(in: .whitespaces) }
        let s = [x.make, model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return s.isEmpty ? nil : s
    }
    /// 0.004 → "1/250"; 2.5 → "2.5s"; 30 → "30s".
    static func shutter(_ seconds: Double) -> String {
        if seconds >= 1 { let s = String(format: "%.1f", seconds); return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + "s" }
        return "1/\(Int((1 / seconds).rounded()))"
    }
}
