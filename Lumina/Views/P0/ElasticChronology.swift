import Foundation

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

    static func label(for chapter: ShootChapter) -> String {
        guard let date = chapter.startedAt else { return "Undated" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d · HH:mm"
        return formatter.string(from: date)
    }
}
