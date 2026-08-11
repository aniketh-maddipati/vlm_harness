// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import Foundation

/// Append-only log of user corrections — feeds taste learning loop.
enum FeedbackStore {
    private static let globalFilename = "feedback_global.json"

    static func log(_ event: FeedbackEvent, project: String) {
        var events = (try? load(project: project)) ?? []
        events.append(event)
        if events.count > 2000 { events.removeFirst(events.count - 2000) }
        try? save(events, project: project)
    }

    static func load(project: String) throws -> [FeedbackEvent] {
        let url = try fileURL(project: project)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([FeedbackEvent].self, from: Data(contentsOf: url))
    }

    static func loadGlobal() -> [FeedbackEvent] {
        let url = globalURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([FeedbackEvent].self, from: data) else { return [] }
        return events
    }

    static func appendGlobal(_ event: FeedbackEvent) {
        var events = loadGlobal()
        events.append(event)
        if events.count > 5000 { events.removeFirst(events.count - 5000) }
        let url = globalURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func save(_ events: [FeedbackEvent], project: String) throws {
        let url = try fileURL(project: project)
        let data = try JSONEncoder().encode(events)
        try data.write(to: url, options: .atomic)
    }

    private static func fileURL(project: String) throws -> URL {
        try ProjectStore.projectDirectory(for: project).appendingPathComponent("feedback.json")
    }

    private static func globalURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumina/feedback_global.json")
        return base
    }
}

enum TasteLearning {
    /// Merge feedback into taste index — hero/keep events become weighted taste entries.
    static func ingestFeedback(_ events: [FeedbackEvent], into entries: inout [TasteEntry], project: String) {
        for event in events where event.kind == .keep || event.kind == .hero {
            guard let recipe = event.recipe, let embedding = event.embedding else { continue }
            let entry = TasteEntry(
                filename: "feedback-\(event.filename)",
                path: event.filename,
                recipe: recipe,
                embedding: embedding
            )
            entries.append(entry)
        }
        entries = dedupe(entries, max: 500)
        try? TasteIndex.save(entries: entries, project: project)
    }

    static func learnFromUserDecision(
        photo: PhotoRecord,
        kind: FeedbackKind,
        projectName: String
    ) {
        var recipe = photo.effectiveRecipe
        recipe.confidence = min(recipe.confidence + 0.15, 0.95)
        let event = FeedbackEvent(
            photoID: photo.id,
            kind: kind,
            recipe: kind == .reject ? nil : recipe,
            embedding: photo.embedding,
            filename: photo.filename,
            weight: kind == .hero ? 1.5 : 1.0
        )
        FeedbackStore.log(event, project: projectName)
        FeedbackStore.appendGlobal(event)

        var library = (try? TasteIndex.load(project: projectName)) ?? []
        if kind == .keep || kind == .hero {
            TasteLearning.ingestFeedback([event], into: &library, project: projectName)
        }
    }

    /// Rebuild the visible taste portrait from accepted keeps/heroes, including audit rescues.
    static func learnedProfile(projectName: String, fallback: DevelopRecipe) -> (DevelopRecipe, Int) {
        let events = (try? FeedbackStore.load(project: projectName)) ?? []
        let sources = events.compactMap { event -> (DevelopRecipe, String)? in
            guard event.kind == .keep || event.kind == .hero, let recipe = event.recipe else { return nil }
            return (recipe, event.filename)
        }
        guard var profile = sources.first?.0 else { return (fallback, 0) }
        for (offset, source) in sources.dropFirst().enumerated() {
            profile = .lerp(profile, source.0, t: 1 / Double(offset + 2))
        }
        profile.sourceNeighbors = sources.map(\.1)
        profile.confidence = min(0.95, 0.45 + Double(sources.count) * 0.05)
        return (profile, sources.count)
    }

    private static func dedupe(_ entries: [TasteEntry], max: Int) -> [TasteEntry] {
        Array(entries.suffix(max))
    }
}
