import Foundation

// MARK: - Plan vocabulary

/// Which frames a step touches, named by relationship — never by ID.
///
/// The model chooses a scope; the app resolves it from data it already owns
/// (bursts, moments, the set, the selection, similarity). A model can therefore
/// never address a frame that doesn't exist or wasn't meant.
nonisolated enum AskScope: String, Codable, CaseIterable, Sendable {
    case frame      // the focused frame
    case burst      // the focused frame's burst
    case similar    // frames that look like the focused one
    case moment     // the focused frame's moment
    case set        // the kept set
    case selection  // what the photographer selected
}

/// Tone groups for sync, matching the drawer's sync chips.
nonisolated enum AskSyncGroup: String, Codable, CaseIterable, Sendable {
    case light, color, detail, profile
}

/// A relative move. Every field is optional; nil means untouched.
nonisolated struct AskDelta: Codable, Equatable, Sendable {
    var exposure: Double?
    var contrast: Double?
    var highlights: Double?
    var shadows: Double?
    var temperature: Double?
    var tint: Double?
    var vibrance: Double?
    var saturation: Double?

    init(
        exposure: Double? = nil, contrast: Double? = nil, highlights: Double? = nil,
        shadows: Double? = nil, temperature: Double? = nil, tint: Double? = nil,
        vibrance: Double? = nil, saturation: Double? = nil
    ) {
        self.exposure = exposure; self.contrast = contrast; self.highlights = highlights
        self.shadows = shadows; self.temperature = temperature; self.tint = tint
        self.vibrance = vibrance; self.saturation = saturation
    }

    var isEmpty: Bool {
        [exposure, contrast, highlights, shadows, temperature, tint, vibrance, saturation]
            .allSatisfy { $0 == nil }
    }

    /// How far one ask may move a control in a single step. Far below slider range:
    /// a sentence nudges; the drawer is for big moves.
    enum Bound {
        static let exposure = 1.0
        static let tone = 40.0
        static let temperature = 1500.0
        static let tint = 30.0
    }

    /// Clamped copy — the engine, not the model, decides how far a sentence can reach.
    var bounded: AskDelta {
        func c(_ v: Double?, _ limit: Double) -> Double? { v.map { min(max($0, -limit), limit) } }
        return AskDelta(
            exposure: c(exposure, Bound.exposure),
            contrast: c(contrast, Bound.tone),
            highlights: c(highlights, Bound.tone),
            shadows: c(shadows, Bound.tone),
            temperature: c(temperature, Bound.temperature),
            tint: c(tint, Bound.tint),
            vibrance: c(vibrance, Bound.tone),
            saturation: c(saturation, Bound.tone)
        )
    }

    func apply(to recipe: EditRecipe) -> EditRecipe {
        let d = bounded
        return recipe.updating { r in
            if let v = d.exposure { r.exposure = min(max(r.exposure + v, -3), 3) }
            if let v = d.contrast { r.contrast = min(max(r.contrast + v, -100), 100) }
            if let v = d.highlights { r.highlights = min(max(r.highlights + v, -100), 100) }
            if let v = d.shadows { r.shadows = min(max(r.shadows + v, -100), 100) }
            if let v = d.temperature { r.temperature = min(max(r.temperature + v, 2000), 12000) }
            if let v = d.tint { r.tint = min(max(r.tint + v, -150), 150) }
            if let v = d.vibrance { r.vibrance = min(max(r.vibrance + v, -100), 100) }
            if let v = d.saturation { r.saturation = min(max(r.saturation + v, -100), 100) }
        }
    }
}

/// What a step does to its frames. Culling is deliberately absent: keep and reject
/// stay the photographer's.
nonisolated enum AskAction: Equatable, Sendable {
    case adjust(AskDelta)
    /// Copy these groups from the focused frame onto the scope.
    case syncFromFocus([AskSyncGroup])
    /// 1 as shot · 2 auto · 3 yours.
    case version(Int)
    case auto
}

nonisolated struct AskStep: Equatable, Sendable {
    var scope: AskScope
    var action: AskAction
}

/// An interpreted request, waiting for ⏎ before anything changes.
nonisolated struct AskPlan: Equatable, Sendable {
    var steps: [AskStep]
    /// One line the photographer reads before applying.
    var summary: String
    /// Which planner produced it — shown so a fallback is never mistaken for the model.
    var planner: String
}

// MARK: - Planner

/// Everything a planner may know about the shoot: counts and relationships, not
/// pixels and not IDs. Enough to pick the right scope; nothing to leak.
nonisolated struct AskContext: Sendable, Equatable {
    var route: String
    var focusedFilename: String?
    var scopeCounts: [AskScope: Int]
}

protocol AskPlanner: Sendable {
    func plan(_ request: String, context: AskContext) async throws -> AskPlan
}

nonisolated enum AskPlanError: Error, Equatable, Sendable {
    case nothingUnderstood
}

/// Offline baseline: a handful of phrases → steps. Deterministic, no network.
/// Also the fallback whenever the model can't be reached.
nonisolated struct KeywordAskPlanner: AskPlanner {
    func plan(_ request: String, context: AskContext) async throws -> AskPlan {
        let text = request.lowercased()
        let scope = Self.scope(in: text)
        var delta = AskDelta()
        let strong = text.contains("a lot") || text.contains("much")
        let step = strong ? 2.0 : 1.0

        if text.contains("warmer") || text.contains("warm") { delta.temperature = 300 * step }
        if text.contains("cooler") || text.contains("cool") { delta.temperature = -300 * step }
        if text.contains("brighter") || text.contains("lift") { delta.exposure = 0.3 * step }
        if text.contains("darker") { delta.exposure = -0.3 * step }
        if text.contains("moodier") || text.contains("moody") {
            delta.exposure = -0.2 * step; delta.contrast = 12 * step; delta.vibrance = -8 * step
        }
        if text.contains("punchier") || text.contains("pop") {
            delta.contrast = 15 * step; delta.vibrance = 10 * step
        }
        if text.contains("softer") { delta.contrast = -12 * step; delta.highlights = -10 * step }

        var steps: [AskStep] = []
        if text.contains("match") || text.contains("like this") || text.contains("same as this") {
            steps.append(AskStep(scope: scope == .frame ? .similar : scope,
                                 action: .syncFromFocus([.light, .color, .profile])))
        }
        if !delta.isEmpty { steps.append(AskStep(scope: scope, action: .adjust(delta))) }
        if text.contains("as shot") || text.contains("reset") { steps.append(AskStep(scope: scope, action: .version(1))) }
        if text.contains("auto") { steps.append(AskStep(scope: scope, action: .auto)) }

        guard !steps.isEmpty else { throw AskPlanError.nothingUnderstood }
        return AskPlan(steps: steps, summary: AskPlanText.summary(steps, context: context), planner: "keywords")
    }

    static func scope(in text: String) -> AskScope {
        if text.contains("burst") { return .burst }
        if text.contains("similar") || text.contains("like it") { return .similar }
        if text.contains("moment") || text.contains("scene") { return .moment }
        if text.contains("the set") || text.contains("kept") { return .set }
        if text.contains("selected") || text.contains("selection") { return .selection }
        return .frame
    }
}

/// A local language model plans (D67: loopback only); the scope vocabulary and bounds
/// keep it honest. Only the request text and scope counts are sent — no images, no
/// filenames beyond the focused one, no IDs.
nonisolated struct ModelAskPlanner: AskPlanner {
    let client: ChatCompletionsClient

    func plan(_ request: String, context: AskContext) async throws -> AskPlan {
        let json = try await client.completeJSON(
            system: Self.systemPrompt,
            user: Self.userPrompt(request, context: context),
            schemaName: "ask_plan",
            schemaJSON: Self.schemaJSON
        )
        let steps = Self.steps(from: json)
        guard !steps.isEmpty else { throw AskPlanError.nothingUnderstood }
        return AskPlan(steps: steps, summary: AskPlanText.summary(steps, context: context), planner: "model")
    }

    /// Parses defensively: an unknown scope or action drops that step rather than guessing.
    static func steps(from json: [String: Any]) -> [AskStep] {
        guard let raw = json["steps"] as? [[String: Any]] else { return [] }
        return raw.compactMap { entry in
            guard let scopeName = entry["scope"] as? String,
                  let scope = AskScope(rawValue: scopeName),
                  let actionName = entry["action"] as? String else { return nil }
            switch actionName {
            case "adjust":
                let d = entry["delta"] as? [String: Any] ?? [:]
                func n(_ k: String) -> Double? {
                    guard let v = (d[k] as? NSNumber)?.doubleValue, v.isFinite, v != 0 else { return nil }
                    return v
                }
                let delta = AskDelta(
                    exposure: n("exposure"), contrast: n("contrast"), highlights: n("highlights"),
                    shadows: n("shadows"), temperature: n("temperature"), tint: n("tint"),
                    vibrance: n("vibrance"), saturation: n("saturation")
                )
                return delta.isEmpty ? nil : AskStep(scope: scope, action: .adjust(delta))
            case "sync":
                let groups = (entry["groups"] as? [String] ?? []).compactMap(AskSyncGroup.init(rawValue:))
                return AskStep(scope: scope, action: .syncFromFocus(groups.isEmpty ? [.light, .color] : groups))
            case "version":
                guard let v = (entry["version"] as? NSNumber)?.intValue, (1...3).contains(v) else { return nil }
                return AskStep(scope: scope, action: .version(v))
            case "auto":
                return AskStep(scope: scope, action: .auto)
            default:
                return nil
            }
        }
    }

    static let systemPrompt = """
    You translate a photographer's editing request into a short plan for a photo culling app. \
    You never see the photos. Choose the smallest scope that matches what they asked: \
    frame (the photo on screen), burst (its rapid sequence), similar (photos that look like it), \
    moment (everything shot around the same time), set (the kept photos), selection. \
    Actions: adjust (relative change; exposure in EV, temperature in Kelvin, others -100..100, \
    prefer small moves), sync (copy groups light/color/detail/profile from the photo on screen \
    to the scope), version (1 as shot, 2 auto, 3 the photographer's own), auto. \
    Never cull. Use as few steps as possible. For adjust, set unused delta fields to 0; \
    for non-sync steps use an empty groups list; for non-version steps use version 0.
    """

    static func userPrompt(_ request: String, context: AskContext) -> String {
        let counts = AskScope.allCases
            .map { "\($0.rawValue): \(context.scopeCounts[$0] ?? 0)" }
            .joined(separator: ", ")
        return """
        Request: \(request)
        On screen: \(context.focusedFilename ?? "nothing focused") (route: \(context.route)).
        Frames per scope: \(counts).
        """
    }

    static let schemaJSON = """
    {"type":"object","additionalProperties":false,"required":["steps"],
     "properties":{"steps":{"type":"array","items":{
       "type":"object","additionalProperties":false,
       "required":["scope","action","delta","groups","version"],
       "properties":{
         "scope":{"type":"string","enum":["frame","burst","similar","moment","set","selection"]},
         "action":{"type":"string","enum":["adjust","sync","version","auto"]},
         "delta":{"type":"object","additionalProperties":false,
           "required":["exposure","contrast","highlights","shadows","temperature","tint","vibrance","saturation"],
           "properties":{"exposure":{"type":"number"},"contrast":{"type":"number"},
             "highlights":{"type":"number"},"shadows":{"type":"number"},
             "temperature":{"type":"number"},"tint":{"type":"number"},
             "vibrance":{"type":"number"},"saturation":{"type":"number"}}},
         "groups":{"type":"array","items":{"type":"string","enum":["light","color","detail","profile"]}},
         "version":{"type":"integer"}}}}}}
    """
}

/// Model first, keywords when the model can't be reached or understands nothing.
nonisolated struct FallbackAskPlanner: AskPlanner {
    let primary: (any AskPlanner)?
    let fallback: any AskPlanner

    func plan(_ request: String, context: AskContext) async throws -> AskPlan {
        if let primary, let plan = try? await primary.plan(request, context: context) {
            return plan
        }
        return try await fallback.plan(request, context: context)
    }
}

// MARK: - Copy

nonisolated enum AskPlanText {
    static func summary(_ steps: [AskStep], context: AskContext) -> String {
        steps.map { step in
            let count = context.scopeCounts[step.scope] ?? 0
            let noun = count == 1 ? "frame" : "frames"
            return "\(describe(step.action)) → \(step.scope.rawValue) · \(count) \(noun)"
        }.joined(separator: "; ")
    }

    static func describe(_ action: AskAction) -> String {
        switch action {
        case .adjust(let d):
            let d = d.bounded
            var parts: [String] = []
            if let v = d.exposure { parts.append(String(format: "%+.2f EV", v)) }
            if let v = d.temperature { parts.append(String(format: "%+.0f K", v)) }
            if let v = d.tint { parts.append(String(format: "tint %+.0f", v)) }
            if let v = d.contrast { parts.append(String(format: "contrast %+.0f", v)) }
            if let v = d.highlights { parts.append(String(format: "highlights %+.0f", v)) }
            if let v = d.shadows { parts.append(String(format: "shadows %+.0f", v)) }
            if let v = d.vibrance { parts.append(String(format: "vibrance %+.0f", v)) }
            if let v = d.saturation { parts.append(String(format: "saturation %+.0f", v)) }
            return parts.joined(separator: " ")
        case .syncFromFocus(let groups):
            return "match " + groups.map(\.rawValue).joined(separator: "+")
        case .version(let v):
            return ["", "as shot", "auto", "yours"][min(max(v, 0), 3)]
        case .auto:
            return "auto"
        }
    }
}
