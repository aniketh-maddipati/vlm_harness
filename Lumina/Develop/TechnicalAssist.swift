import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Experimental opt-in controller. Never applies a recipe or reads reference edits.
/// Observations are model hypotheses; measured constraints own action authority.
nonisolated enum TechnicalAssist {
    static let version = "sony-technical-v0-1"
    static let enabledByDefault = false
    static let deadlineSeconds = 8.0

    enum Action: String, Codable, CaseIterable, Sendable {
        case neutral, auto, liftExposure, lowerExposure, recoverHighlights, abstain
    }

    struct Decision: Sendable {
        let action: Action
        let recipe: EditRecipe
        let hypothesis: String
        let reason: String
        let rawReply: String?
        let elapsedMS: Double
        var needsReview: Bool { action == .abstain }
    }

    /// Fixed engineering limits, not fitted to this photographer's edits.
    /// A one-third stop is the only exposure proposal. No colour or geometry moves.
    static func recipe(_ action: Action, base: EditRecipe, stats: ImageStats) -> EditRecipe? {
        guard valid(stats) else { return action == .neutral || action == .abstain ? base : nil }
        switch action {
        case .neutral, .abstain: return base
        case .liftExposure:
            guard stats.mean < 0.30, stats.highlightClipFraction < 0.005 else { return nil }
            return base.updating { $0.exposure += 1.0 / 3.0 }
        case .lowerExposure:
            guard stats.mean > 0.65, stats.shadowClipFraction < 0.005 else { return nil }
            return base.updating { $0.exposure -= 1.0 / 3.0 }
        case .recoverHighlights:
            guard stats.highlightClipFraction > 0.005 else { return nil }
            return base.updating { $0.highlights = -20 }
        case .auto:
            // The old Auto still has unvalidated exposure, WB and geometry behavior.
            // It stays an evaluation arm, never an executable action in v0.
            return nil
        }
    }

    static func valid(_ stats: ImageStats) -> Bool {
        [stats.mean, stats.highlightClipFraction, stats.shadowClipFraction].allSatisfy {
            $0.isFinite && (0...1).contains($0)
        } && stats.sampleCount > 0
    }

    static func deterministicAction(_ stats: ImageStats) -> Action {
        guard valid(stats) else { return .abstain }
        if stats.highlightClipFraction > 0.005 { return .recoverHighlights }
        if stats.mean < 0.30 && stats.highlightClipFraction < 0.005 { return .liftExposure }
        if stats.mean > 0.65 && stats.shadowClipFraction < 0.005 { return .lowerExposure }
        return .neutral
    }

    static func parse(_ json: [String: Any], base: EditRecipe, stats: ImageStats) -> Decision {
        let raw = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) }
        guard Set(json.keys) == Set(["action", "observation"]),
              let value = json["action"] as? String, let action = Action(rawValue: value),
              let observation = json["observation"] as? String, observation.utf8.count <= 512,
              let candidate = recipe(action, base: base, stats: stats) else {
            return Decision(action: .abstain, recipe: base, hypothesis: "", reason: "invalid or measurement-inconsistent action", rawReply: raw, elapsedMS: 0)
        }
        return Decision(action: action, recipe: candidate, hypothesis: observation,
                        reason: action == .abstain ? "model requested review" : "bounded proposal; rendered review required",
                        rawReply: raw, elapsedMS: 0)
    }

    /// Explicitly supplied neutral RAW render, never a camera JPEG or hand edit.
    /// Caller records and reviews the rendered result; nothing is silently committed.
    static func propose(neutralJPEG: Data, base: EditRecipe, stats: ImageStats,
                        client: ChatCompletionsClient) async -> Decision {
        let start = Date()
        func fallback(_ reason: String) -> Decision {
            Decision(action: .abstain, recipe: base, hypothesis: "", reason: reason,
                     rawReply: nil, elapsedMS: Date().timeIntervalSince(start) * 1000)
        }
        guard !Task.isCancelled else { return fallback("cancelled") }
        guard valid(stats), neutralJPEG.count <= 512_000,
              let source = CGImageSourceCreateWithData(neutralJPEG as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              max(width, height) <= 512 else { return fallback("invalid neutral render or measurements") }
        var endpoint = client.endpoint
        endpoint.timeout = min(endpoint.timeout, deadlineSeconds)
        let bounded = ChatCompletionsClient(endpoint: endpoint, transport: client.transport)
        do {
            let json = try await bounded.completeJSON(system: "Choose a conservative technical starting point. The image is an accurate neutral RAW render. Observations are hypotheses, not facts. Do not invent a style. Abstain if uncertain. Return only the schema.",
                user: "Mean luma \(stats.mean); highlight clipping \(stats.highlightClipFraction); shadow clipping \(stats.shadowClipFraction). Actions: neutral (usual answer); liftExposure (+1/3 EV, only dark low-clip frames); lowerExposure (-1/3 EV, only bright low-shadow-clip frames); recoverHighlights (-20, clipping only); abstain. Auto is unavailable pending validation. No geometry or colour edits.",
                imageJPEG: neutralJPEG, schemaName: "technical_action", schemaJSON: schema)
            guard !Task.isCancelled else { return fallback("cancelled") }
            guard Date().timeIntervalSince(start) <= deadlineSeconds else { return fallback("deadline exceeded") }
            let result = parse(json, base: base, stats: stats)
            return Decision(action: result.action, recipe: result.recipe, hypothesis: result.hypothesis,
                            reason: result.reason, rawReply: result.rawReply,
                            elapsedMS: Date().timeIntervalSince(start) * 1000)
        } catch { return fallback("local model unavailable") }
    }

    static let schema = """
    {"type":"object","additionalProperties":false,"required":["action","observation"],"properties":{"action":{"type":"string","enum":["neutral","liftExposure","lowerExposure","recoverHighlights","abstain"]},"observation":{"type":"string","maxLength":512}}}
    """
}
