import Foundation
import CoreGraphics

/// Presentation only: existing chapters and the caller's order remain authoritative.
@MainActor
enum ElasticChronology {
    enum AxisOrientation: Equatable, Sendable {
        case vertical
        case horizontal
    }

    /// One chapter mark on the progress axis after floor adjustment.
    struct Node: Identifiable, Equatable, Sendable {
        var id: String { chapterID }
        var chapterID: String
        var label: String
        /// Distance along the axis in viewport-length units (1 = one full track).
        var position: CGFloat
        var isUndated: Bool
    }

    /// A ruler mark on the solid time axis. Independent of chapter nodes.
    struct Tick: Identifiable, Equatable, Sendable {
        var id: String { "\(position)-\(label)-\(major)" }
        var position: CGFloat
        var label: String
        var major: Bool
    }

    /// How finely the axis names time. Same-hour shoots start on minutes.
    enum TickResolution: Equatable, Sendable {
        case seconds
        case minutes
        case hours
        case days
    }

    /// Laid-out axis: positions may extend past 1 when scale or floor demands scroll.
    struct Placement: Equatable, Sendable {
        var nodes: [Node]
        var ticks: [Tick]
        /// Total axis length in viewport units; ≥ 1.
        var contentLength: CGFloat
        var shortWindow: Bool
        var resolution: TickResolution?
    }

    static func boundaries(orderedIDs: [UUID], chapters: [ShootChapter], chronological: Bool) -> [UUID: ShootChapter] {
        guard chronological else { return [:] }
        var byAsset: [UUID: ShootChapter] = [:]
        for chapter in chapters {
            for id in chapter.assetIDs { byAsset[id] = chapter }
        }
        var result: [UUID: ShootChapter] = [:]
        var previousChapter: String?
        for id in orderedIDs {
            let chapter = byAsset[id]
            if let chapter, chapter.id != previousChapter { result[id] = chapter }
            previousChapter = chapter?.id
        }
        return result
    }

    /// The chapter crossing the viewport's leading edge owns the navigation marker.
    /// Before the first realized chapter reaches that edge, choose the nearest next one.
    static func activeChapter(frames: [String: CGRect], leadingEdge: CGFloat = 0) -> String? {
        let ordered = frames.filter { !$0.value.isEmpty }.sorted {
            $0.value.minY == $1.value.minY ? $0.key < $1.key : $0.value.minY < $1.value.minY
        }
        return ordered.last(where: { $0.value.minY <= leadingEdge })?.key ?? ordered.first?.key
    }

    /// Dated chapters by capture time; undated chapters keep relative order at the end.
    static func orderedForAxis(_ chapters: [ShootChapter]) -> [ShootChapter] {
        let dated = chapters.filter { $0.startedAt != nil }.sorted {
            ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast)
        }
        let undated = chapters.filter { $0.startedAt == nil }
        return dated + undated
    }

    static func label(for chapter: ShootChapter, shortWindow: Bool) -> String {
        guard let date = chapter.startedAt else { return "Undated" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = shortWindow ? "HH:mm:ss" : "MMM d · HH:mm"
        return formatter.string(from: date)
    }

    static func label(for chapter: ShootChapter) -> String {
        label(for: chapter, shortWindow: false)
    }

    /// True when the shoot spans under a few minutes, or time-proportional nodes
    /// would sit closer than the floor gap.
    static func isShortWindow(
        chapters: [ShootChapter],
        floorGap: CGFloat = ElasticLayout.ChronAxis.floorGap
    ) -> Bool {
        let ordered = orderedForAxis(chapters)
        let dated = ordered.compactMap(\.startedAt)
        guard let first = dated.first, let last = dated.last, dated.count >= 2 else {
            return true
        }
        let span = last.timeIntervalSince(first)
        if span < ElasticLayout.ChronAxis.shortWindowSeconds { return true }
        guard span > 0 else { return true }
        var previous: CGFloat = 0
        var seen = false
        for date in dated {
            let fraction = CGFloat(date.timeIntervalSince(first) / span)
            if seen, fraction - previous < floorGap { return true }
            previous = fraction
            seen = true
        }
        return false
    }

    /// Progress-bar node placement. Manual set order (`chronological: false`) yields no nodes.
    static func placement(
        chapters: [ShootChapter],
        chronological: Bool,
        scale: CGFloat = ElasticLayout.ChronAxis.unitLength,
        floorGap: CGFloat = ElasticLayout.ChronAxis.floorGap
    ) -> Placement {
        let unit = ElasticLayout.ChronAxis.unitLength
        guard chronological, !chapters.isEmpty else {
            return Placement(nodes: [], ticks: [], contentLength: unit, shortWindow: false, resolution: nil)
        }

        let ordered = orderedForAxis(chapters)
        let shortWindow = isShortWindow(chapters: ordered, floorGap: floorGap)
        let scaleClamped = min(
            max(scale, ElasticLayout.ChronAxis.scaleMin),
            ElasticLayout.ChronAxis.scaleMax
        )

        var raw: [CGFloat] = Array(repeating: 0, count: ordered.count)
        if ordered.count == 1 {
            raw = [0]
        } else if shortWindow {
            let last = CGFloat(ordered.count - 1)
            raw = ordered.indices.map { CGFloat($0) / last }
        } else {
            let dated = ordered.compactMap(\.startedAt)
            let start = dated.first ?? .distantPast
            let end = dated.last ?? start
            let span = max(end.timeIntervalSince(start), TimeInterval.leastNonzeroMagnitude)
            var lastDatedFraction: CGFloat = 0
            for index in ordered.indices {
                if let date = ordered[index].startedAt {
                    let fraction = CGFloat(date.timeIntervalSince(start) / span)
                    raw[index] = fraction
                    lastDatedFraction = max(lastDatedFraction, fraction)
                } else {
                    lastDatedFraction += floorGap
                    raw[index] = lastDatedFraction
                }
            }
        }

        raw = raw.map { $0 * scaleClamped }

        if let origin = raw.first {
            raw = raw.map { $0 - origin }
        }

        for index in raw.indices.dropFirst() {
            let floor = raw[index - 1] + floorGap
            if raw[index] < floor {
                raw[index] = floor
            }
        }

        let axisTicks = Self.ticks(
            chapters: ordered,
            chronological: true,
            scale: scaleClamped,
            floorGap: floorGap
        )
        let contentLength = max(raw.last ?? unit, axisTicks.marks.last.map(\.position) ?? 0, unit)
        let nodes = zip(ordered, raw).map { chapter, position in
            Node(
                chapterID: chapter.id,
                label: label(for: chapter, shortWindow: shortWindow),
                position: position,
                isUndated: chapter.startedAt == nil
            )
        }
        return Placement(
            nodes: nodes,
            ticks: axisTicks.marks,
            contentLength: contentLength,
            shortWindow: shortWindow,
            resolution: axisTicks.resolution
        )
    }

    /// Solid-axis resolution: a shoot that stays inside one hour always names minutes,
    /// even before pinch. Pinch then steps minutes → seconds the way Photos does.
    static func tickResolution(
        chapters: [ShootChapter],
        scale: CGFloat = ElasticLayout.ChronAxis.unitLength
    ) -> TickResolution? {
        ticks(
            chapters: chapters,
            chronological: true,
            scale: scale
        ).resolution
    }

    static func ticks(
        chapters: [ShootChapter],
        chronological: Bool,
        scale: CGFloat = ElasticLayout.ChronAxis.unitLength,
        floorGap: CGFloat = ElasticLayout.ChronAxis.floorGap
    ) -> (marks: [Tick], resolution: TickResolution?) {
        guard chronological else { return ([], nil) }
        let dated = orderedForAxis(chapters).compactMap(\.startedAt)
        guard let first = dated.first, let last = dated.last else { return ([], nil) }

        let scaleClamped = min(
            max(scale, ElasticLayout.ChronAxis.scaleMin),
            ElasticLayout.ChronAxis.scaleMax
        )
        let span = max(last.timeIntervalSince(first), TimeInterval.leastNonzeroMagnitude)
        let visible = span / TimeInterval(scaleClamped)
        let calendar = Calendar.current
        let sameMinute = calendar.isDate(first, equalTo: last, toGranularity: .minute)
        let sameHour = calendar.isDate(first, equalTo: last, toGranularity: .hour)
        let sameDay = calendar.isDate(first, equalTo: last, toGranularity: .day)

        let resolution: TickResolution
        if sameMinute || visible <= ElasticLayout.ChronAxis.minuteSeconds * 2 {
            resolution = .seconds
        } else if sameHour || visible <= ElasticLayout.ChronAxis.hourSeconds * 2 {
            resolution = .minutes
        } else if sameDay || visible <= ElasticLayout.ChronAxis.daySeconds * 2 {
            resolution = .hours
        } else {
            resolution = .days
        }

        let step: TimeInterval
        let majorEvery: Int
        switch resolution {
        case .seconds:
            step = ElasticLayout.ChronAxis.secondTick
            majorEvery = 3
        case .minutes:
            step = ElasticLayout.ChronAxis.minuteTick
            majorEvery = 3
        case .hours:
            step = ElasticLayout.ChronAxis.hourSeconds
            majorEvery = 3
        case .days:
            step = ElasticLayout.ChronAxis.daySeconds
            majorEvery = 1
        }

        let origin = aligned(first, step: step, calendar: calendar)
        var cursor = origin
        var raw: [(Date, Bool)] = []
        var index = 0
        let limit = last.addingTimeInterval(step)
        while cursor <= limit {
            if cursor >= first.addingTimeInterval(-step) {
                raw.append((cursor, index % majorEvery == 0))
            }
            guard let next = calendar.date(byAdding: .second, value: Int(step.rounded()), to: cursor) else { break }
            if next <= cursor { break }
            cursor = next
            index += 1
            if raw.count > 80 { break }
        }
        if raw.last?.0 ?? first < last {
            raw.append((last, true))
        }

        var marks: [Tick] = raw.map { date, major in
            let fraction = CGFloat(date.timeIntervalSince(first) / span) * scaleClamped
            return Tick(
                position: max(0, fraction),
                label: major ? tickLabel(date, resolution: resolution) : "",
                major: major
            )
        }
        marks = thin(marks, floorGap: floorGap)
        return (marks, resolution)
    }

    private static func aligned(_ date: Date, step: TimeInterval, calendar: Calendar) -> Date {
        let components: Set<Calendar.Component>
        if step >= ElasticLayout.ChronAxis.daySeconds {
            components = [.year, .month, .day]
        } else if step >= ElasticLayout.ChronAxis.hourSeconds {
            components = [.year, .month, .day, .hour]
        } else if step >= ElasticLayout.ChronAxis.minuteSeconds {
            components = [.year, .month, .day, .hour, .minute]
        } else {
            var exact = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let second = exact.second ?? 0
            exact.second = second - (second % max(Int(step.rounded()), 1))
            return calendar.date(from: exact) ?? date
        }
        return calendar.date(from: calendar.dateComponents(components, from: date)) ?? date
    }

    private static func tickLabel(_ date: Date, resolution: TickResolution) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        switch resolution {
        case .seconds: formatter.dateFormat = "HH:mm:ss"
        case .minutes: formatter.dateFormat = "HH:mm"
        case .hours: formatter.dateFormat = "HH:mm"
        case .days: formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }

    private static func thin(_ ticks: [Tick], floorGap: CGFloat) -> [Tick] {
        guard ticks.count > 1 else { return ticks }
        var kept: [Tick] = []
        for tick in ticks {
            if let previous = kept.last, tick.position - previous.position < floorGap {
                if tick.major, !previous.major {
                    kept.removeLast()
                    kept.append(tick)
                }
                continue
            }
            kept.append(tick)
        }
        if let last = ticks.last, kept.last?.position != last.position {
            if let previous = kept.last, last.position - previous.position < floorGap {
                if last.major { kept[kept.count - 1] = last }
            } else {
                kept.append(last)
            }
        }
        return kept
    }
}
