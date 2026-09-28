import Foundation

/// Port of `buildShoot` from `design/handoff/lumina-cull/lumina-core.js`.
/// Photos → rows (gap > 90 s), groups (< 1 s apart; bracket = 3+ frames spanning −/+ EV),
/// flags (soft / blown / shake), ranks, suggested keeps and navigation nodes.
nonisolated struct CullCoreShoot {
    /// One photo as read from disk: parsed header fields plus `CullCoreMeasure` of its preview.
    struct Input: Equatable {
        var name: String
        /// Path relative to the opened folder; breaks capture-time ties.
        var path: String
        var date: String?
        var exposure: Double?
        var focalLength: Double?
        var exposureBias: Double?
        var luminance: Double
        var focus: Double
        var clip: Double
        var portrait = false
        /// Existing sidecar path and contents, and whether it already carries Lightroom develop settings.
        var xmpPath: String?
        var xmp: String?
        var lightroomEdited = false
    }

    enum Light: String { case morning, midday, afternoon, evening }
    enum GroupKind: String { case single, burst, bracket }
    enum SubKind: String { case singles, burst, bracket }

    struct Photo: Equatable {
        /// `f<n>` — n is the index in shoot order.
        var id: String
        var n: Int
        var input: Input
        /// UTC milliseconds parsed from `date` (0 when missing), as JS `Date.UTC`.
        var t: Double
        var moment: Int
        /// `HH:MM` of the row this photo belongs to.
        var time: String
        var hour: Int
        var light: Light
        /// Focus percentile across the shoot, 0–100.
        var sharp: Int
        var clip: Double
        var blown: Bool
        var shake: Bool
        /// Starts a new group unless `cuts` says otherwise.
        var start: Bool
        var soft = false
        var slight = false
        var inBracket = false
        var rank = 0
        var groupSize = 0
        var kind: GroupKind = .single
        var groupID = ""
        /// `1/500`, `2.0s`, or empty.
        var shutter: String
        /// Rounded focal length in mm, 0 when unknown (a Double: a 0-denominator rational is ∞ in JS too).
        var focalMM: Double
    }

    struct Group: Equatable {
        var id: String
        var kind: GroupKind
        /// Photo indices in shoot order.
        var frames: [Int]
        /// Bracket: shoot order. Otherwise sharpest first.
        var ranked: [Int]
    }

    /// A group as shown in a row: bursts and brackets stand alone, runs of singles collapse.
    struct Sub: Equatable {
        var id: String
        var kind: SubKind
        var groupID: String?
        var frames: [Int]
    }

    struct Moment: Equatable {
        var id: String
        var index: Int
        var hour: Int
        var time: String
        var light: Light
        var frames: [Int]
        var groups: [String]
        var subs: [Sub]
    }

    struct NavNode: Equatable {
        enum Level: String { case moment, sub }
        var id: String
        var level: Level
        var moment: Int
        var ids: [String]
        var kind: SubKind?
    }

    var photos: [Photo]
    var moments: [Moment]
    /// In creation order (JS object insertion order).
    var groups: [Group]
    var nodes: [NavNode]
    /// Photo id → the sub (row group) it sits in.
    var subOf: [String: String]
    /// Photo ids in the order the prototype adds them.
    var suggestedKeeps: [String]
    var order: [String]

    func photo(_ id: String) -> Photo? {
        guard id.hasPrefix("f"), let n = Int(id.dropFirst()), photos.indices.contains(n) else { return nil }
        return photos[n]
    }

    func group(_ id: String) -> Group? { groups.first { $0.id == id } }

    /// `cuts[photoID] = true` splits a group before that photo; `false` merges it into the previous one.
    static func build(_ list: [Input], cuts: [String: Bool] = [:]) -> CullCoreShoot {
        let sorted = list.enumerated().map { (index: $0.offset, input: $0.element, t: timestamp($0.element.date)) }
            .sorted { a, b in
                if a.t != b.t { return a.t < b.t }
                let c = localeCompare(a.input.path, b.input.path)
                return c != .orderedSame ? c == .orderedAscending : a.index < b.index
            }
        let focusSorted = sorted.map(\.input.focus).sorted()
        func percentile(_ v: Double) -> Int {
            var lo = 0, hi = focusSorted.count
            while lo < hi {
                let m = (lo + hi) >> 1
                if focusSorted[m] < v { lo = m + 1 } else { hi = m }
            }
            return Int(CullCoreJSNumber.round(100 * Double(lo) / Double(max(1, focusSorted.count - 1))))
        }

        var photos: [Photo] = []
        var moments: [Moment] = []
        for (idx, q) in sorted.enumerated() {
            let prev = idx > 0 ? sorted[idx - 1] : nil
            let gap = prev.map { (q.t - $0.t) / 1000 } ?? 1e9
            if moments.isEmpty || gap > 90 {
                let hh = utcHour(q.t)
                let time = pad2(hh) + ":" + pad2(utcMinute(q.t))
                moments.append(Moment(id: "m\(moments.count)", index: moments.count, hour: hh, time: time,
                                      light: light(hh), frames: [], groups: [], subs: []))
            }
            let mi = moments.count - 1, n = photos.count, hh = utcHour(q.t)
            let input = q.input
            let fl = CullCoreJSNumber.truthy(input.focalLength) ? input.focalLength! : 0
            let exp = CullCoreJSNumber.truthy(input.exposure) ? input.exposure : nil
            let shake = exp.map { fl != 0 && $0 > 2 / fl } ?? false
            let shutter = exp.map { $0 >= 1 ? CullCoreJSNumber.toFixed($0, 1) + "s"
                : "1/" + CullCoreJSNumber.numberString(CullCoreJSNumber.round(1 / $0)) } ?? ""
            photos.append(Photo(
                id: "f\(n)", n: n, input: input, t: q.t, moment: mi, time: moments[mi].time, hour: hh, light: light(hh),
                sharp: percentile(input.focus), clip: Double(CullCoreJSNumber.toFixed(input.clip, 1)) ?? input.clip,
                blown: input.clip > 2, shake: shake,
                start: prev == nil || gap > 1 || moments[mi].frames.isEmpty,
                shutter: shutter, focalMM: fl != 0 ? CullCoreJSNumber.round(fl) : 0
            ))
            moments[mi].frames.append(n)
        }

        var groups: [Group] = []
        for mi in moments.indices {
            var runs: [[Int]] = []
            for (i, n) in moments[mi].frames.enumerated() {
                let starts = i == 0 ? true : (cuts[photos[n].id] ?? photos[n].start)
                if starts { runs.append([]) }
                runs[runs.count - 1].append(n)
            }
            var momentGroups: [Group] = []
            for run in runs {
                let kind = groupKind(run.map { photos[$0].input.exposureBias })
                for n in run { photos[n].inBracket = kind == .bracket }
                if kind == .burst {
                    let mx = jsMax(run.map { photos[$0].input.focus })
                    for n in run {
                        photos[n].soft = photos[n].input.focus < mx * 0.45
                        photos[n].slight = !photos[n].soft && photos[n].input.focus < mx * 0.7
                    }
                } else {
                    for n in run {
                        photos[n].soft = photos[n].sharp < 12
                        photos[n].slight = !photos[n].soft && photos[n].sharp < 25
                    }
                }
                let ranked = kind == .bracket ? run : stableSorted(run) { photos[$1].input.focus - photos[$0].input.focus }
                for (r, n) in ranked.enumerated() {
                    photos[n].rank = r + 1; photos[n].groupSize = run.count; photos[n].kind = kind
                }
                let gid = "g\(photos[run[0]].n)"
                for n in run { photos[n].groupID = gid }
                momentGroups.append(Group(id: gid, kind: kind, frames: run, ranked: ranked))
            }
            var subs: [Sub] = []
            for g in momentGroups {
                if g.kind == .single {
                    if let last = subs.last, last.kind == .singles { subs[subs.count - 1].frames.append(g.frames[0]) }
                    else { subs.append(Sub(id: "", kind: .singles, groupID: nil, frames: [g.frames[0]])) }
                } else {
                    subs.append(Sub(id: "", kind: g.kind == .bracket ? .bracket : .burst, groupID: g.id, frames: g.frames))
                }
            }
            for s in subs.indices { subs[s].id = subs[s].groupID ?? "r" + photos[subs[s].frames[0]].id }
            moments[mi].groups = momentGroups.map(\.id)
            moments[mi].subs = subs
            groups += momentGroups
        }

        var nodes: [NavNode] = [], subOf: [String: String] = [:]
        for m in moments {
            nodes.append(NavNode(id: m.id, level: .moment, moment: m.index,
                                 ids: m.subs.flatMap { $0.frames.map { photos[$0].id } }, kind: nil))
            for s in m.subs {
                let ids = s.frames.map { photos[$0].id }
                nodes.append(NavNode(id: s.id, level: .sub, moment: m.index, ids: ids, kind: s.kind))
                for id in ids { subOf[id] = s.id }
            }
        }

        var keeps: [String] = [], kept = Set<String>()
        func keep(_ n: Int) { if kept.insert(photos[n].id).inserted { keeps.append(photos[n].id) } }
        for g in groups {
            switch g.kind {
            case .bracket: g.frames.forEach(keep)
            case .burst:
                keep(g.ranked.first { !photos[$0].blown && !photos[$0].shake && !photos[$0].soft } ?? g.ranked[0])
            case .single:
                let p = photos[g.frames[0]]
                if !p.soft && !p.blown && !p.shake { keep(p.n) }
            }
        }
        let order = moments.flatMap { $0.subs.flatMap { $0.frames.map { photos[$0].id } } }
        return CullCoreShoot(photos: photos, moments: moments, groups: groups, nodes: nodes,
                             subOf: subOf, suggestedKeeps: keeps, order: order)
    }

    // MARK: - JS semantics

    private static func light(_ h: Int) -> Light { h < 11 ? .morning : h < 15 ? .midday : h < 18 ? .afternoon : .evening }

    private static func groupKind(_ evs: [Double?]) -> GroupKind {
        if evs.count < 2 { return .single }
        guard evs.count >= 3, evs.allSatisfy({ $0 != nil }) else { return .burst }
        let values = evs.map { $0! }
        let distinct = Set(values.map { CullCoreJSNumber.toFixed($0, 1) }).count == values.count
        return distinct && jsMin(values) < 0 && jsMax(values) > 0 ? .bracket : .burst
    }

    /// `Math.max(...xs)` — NaN poisons the result.
    private static func jsMax(_ xs: [Double]) -> Double {
        xs.contains { $0.isNaN } ? .nan : xs.reduce(-.infinity) { Swift.max($0, $1) }
    }

    private static func jsMin(_ xs: [Double]) -> Double {
        xs.contains { $0.isNaN } ? .nan : xs.reduce(.infinity) { Swift.min($0, $1) }
    }

    /// `Array.prototype.sort` with a numeric comparator: stable, NaN treated as equal.
    private static func stableSorted(_ xs: [Int], _ compare: (Int, Int) -> Double) -> [Int] {
        xs.enumerated().sorted { a, b in
            let c = compare(a.element, b.element)
            return c < 0 || (!(c > 0) && a.offset < b.offset)
        }.map(\.element)
    }

    /// `String.prototype.localeCompare` (ICU root collation in V8/JSC).
    private static func localeCompare(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [], range: nil, locale: Locale(identifier: "en_US"))
    }

    private static let datePattern = try! NSRegularExpression(pattern: "^([0-9]{4}):([0-9]{2}):([0-9]{2}) ([0-9]{2}):([0-9]{2}):([0-9]{2})")

    /// `Date.UTC(+y, +mo - 1, +d, +h, +mi, +s)` from an EXIF date, or 0.
    static func timestamp(_ date: String?) -> Double {
        guard let date else { return 0 }
        let ns = date as NSString
        guard let m = datePattern.firstMatch(in: date, range: NSRange(location: 0, length: ns.length)) else { return 0 }
        let f = (1...6).map { Int(ns.substring(with: m.range(at: $0)))! }
        var year = f[0]
        if (0...99).contains(year) { year += 1900 }  // Date.UTC two-digit-year rule
        let month = f[1] - 1
        let ym = year + Int((Double(month) / 12).rounded(.down)), mn = ((month % 12) + 12) % 12
        let days = daysFromCivil(ym, mn + 1, 1) + (f[2] - 1)
        return Double(days) * 86_400_000 + Double(f[3]) * 3_600_000 + Double(f[4]) * 60_000 + Double(f[5]) * 1000
    }

    private static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func utcHour(_ t: Double) -> Int { Int(positiveMod(t, 86_400_000) / 3_600_000) }
    private static func utcMinute(_ t: Double) -> Int { Int(positiveMod(t, 3_600_000) / 60_000) }
    private static func positiveMod(_ a: Double, _ b: Double) -> Double { let r = a.truncatingRemainder(dividingBy: b); return r < 0 ? r + b : r }
    private static func pad2(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
}
