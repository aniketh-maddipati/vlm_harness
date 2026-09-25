import Foundation
import CoreGraphics

/// Presentation only: existing chapters and the caller's order remain authoritative.
@MainActor
enum ElasticChronology {
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

    static func label(for chapter: ShootChapter) -> String {
        guard let date = chapter.startedAt else { return "Undated" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d · HH:mm"
        return formatter.string(from: date)
    }
}
