import Foundation

// WP-0 contract: the demo card (`LUMINA_CARD=demo117`, `demo:{n}`), a port of the prototype's
// `build()` so ids, scenes, bursts and suggestions match the HTML suites photo for photo.

public extension Shoot {
    static let demo117 = Shoot.demo(117)

    static func demo(_ count: Int) -> Shoot {
        let sf = count > 117 ? Double(count) / 117 : 1
        let rows: [(String, Int)] = [("09:12:40", 14), ("11:40:02", 9), ("14:02:07", 52), ("16:31:15", 18), ("19:14:33", 24)]
            .map { ($0.0, Int((Double($0.1) * sf).rounded())) }
        let lenses: [(String, Double, Double)] = [("FE 85mm F1.4 GM", 85, 2), ("FE 24-70mm F2.8 GM II", 35, 4), ("FE 35mm F1.4 GM", 35, 2.8)]
        let shutters = ["1/250", "1/500", "1/1000", "1/125", "1/60"], isos = [100, 200, 400, 800, 1600]
        let odd: [Int: Double] = [0: 3, 1: 2.0 / 3, 2: 2.0 / 3, 3: 2.0 / 3, 4: 0.4]
        var photos: [Photo] = [], scenes: [PhotoScene] = [], bursts: [Burst] = []
        var n = 3260, gn = 27
        for (ri, row) in rows.enumerated() {
            let t = row.0.split(separator: ":").compactMap { Int($0) }, cnt = row.1
            var ids: [String] = [], k = 0
            while k < cnt {
                let h = (n * 31 + ri * 7) % 11
                let size = h < 3 && cnt - k >= 3 ? min(cnt - k, 3 + (h + n) % 4) : 1
                let gid: String? = size > 1 ? "g\(gn)" : nil
                if let gid { bursts.append(Burst(id: gid, ids: [])); gn += 1 }
                for j in 0..<size {
                    let secs = t[0] * 3600 + t[1] * 60 + t[2] + k
                    let lens = lenses[(ri + (gid != nil ? 0 : k)) % 3], id = "DSC0\(n)"
                    let suggested = gid != nil ? j < (n % 3 != 0 ? 1 : 2) : (n * 13) % 10 < 6
                    photos.append(Photo(
                        id: id, file: id, scene: ri, burst: gid, aspect: gid != nil ? 1.5 : (odd[n % 23] ?? 1.5),
                        time: String(format: "%02d:%02d:%02d", (secs / 3600) % 24, (secs / 60) % 60, secs % 60),
                        camera: "ILCE-7M4", lens: lens.0, focal: lens.1, aperture: lens.2,
                        shutter: shutters[(n + ri) % 5], iso: isos[(n * 3 + ri) % 5],
                        source: .demo(seed: 180 + n % 160, bw: gid == nil && n % 19 == 0), suggested: suggested))
                    ids.append(id)
                    if gid != nil { bursts[bursts.count - 1].ids.append(id) }
                    n += 1; k += 1
                }
            }
            scenes.append(PhotoScene(id: "r\(ri)", index: ri, hm: String(row.0.prefix(5)), ids: ids))
        }
        return Shoot(photos: photos, scenes: scenes, bursts: bursts, name: "Untitled", label: "ILCE-7M4",
                     span: "09:12–19:14", local: false, key: "card-demo-\(photos.count)")
    }

    /// The shoot a launch configuration asks for. Unsplash cards fall back to the scaled demo
    /// until the manifest is bundled (WP-11).
    static func card(_ card: LaunchConfig.Card) -> Shoot? {
        switch card {
        case .demo(let n), .unsplash(let n): return .demo(n)
        case .path, .none: return nil
        }
    }
}
